import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/push_service.dart';
import 'package:magicchat_client/data/push_token_provider.dart';
import 'package:magicchat_client/data/push_registration_store.dart';

class _MemoryPushRegistrationStore extends PushRegistrationStore {
  StoredPushInstallation? installation;
  StoredPushGrant? grant;

  @override
  Future<StoredPushInstallation?> readInstallation() async => installation;

  @override
  Future<void> writeInstallation(StoredPushInstallation value) async {
    installation = value;
  }

  @override
  Future<void> clearInstallation() async => installation = null;

  @override
  Future<StoredPushGrant?> readGrant() async => grant;

  @override
  Future<void> writeGrant(StoredPushGrant value) async => grant = value;

  @override
  Future<void> clearGrant() async => grant = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS 推送平台名称符合 push-gateway 契约', () {
    expect(pushPlatformName(TargetPlatform.iOS), 'ios');
    expect(pushPlatformName(TargetPlatform.android), 'android');
  });

  test('无原生插件时 Push Grant 安全降级', () async {
    final channel = MethodChannel('test/push');
    channel.setMockMethodCallHandler((_) async => null);
    addTearDown(() => channel.setMockMethodCallHandler(null));
    expect(
        await const PushTokenProvider(channel: MethodChannel('test/push'))
            .readGrant(),
        isNull);
  });

  test('拒绝已过期的原生令牌', () async {
    final channel = MethodChannel('test/push-expired');
    channel.setMockMethodCallHandler((_) async => {
          'grant_id': 'grant',
          'installation_id': 'install',
          'send_token': 'token',
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        });
    addTearDown(() => channel.setMockMethodCallHandler(null));
    expect(
        await const PushTokenProvider(
                channel: MethodChannel('test/push-expired'))
            .readGrant(),
        isNull);
  });

  test('读取并规范化原生 APNs 设备令牌', () async {
    final channel = MethodChannel('test/apns-device-token');
    channel.setMockMethodCallHandler((_) async => {
          'provider': 'apns',
          'platform': 'ios',
          'environment': 'development',
          'token': '  ${'a' * 64}  ',
        });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    final token = await const PushTokenProvider(
            channel: MethodChannel('test/apns-device-token'))
        .readDeviceToken();

    expect(token?.provider, 'apns');
    expect(token?.platform, 'ios');
    expect(token?.environment, 'development');
    expect(token?.token, 'a' * 64);
  });

  test('读取有效 Android JPush RegistrationID', () async {
    final channel = MethodChannel('test/jpush-device-token');
    channel.setMockMethodCallHandler((_) async => {
          'provider': 'jpush',
          'platform': 'android',
          'environment': 'production',
          'token': '  registration-id  ',
        });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    final token = await const PushTokenProvider(
            channel: MethodChannel('test/jpush-device-token'))
        .readDeviceToken();

    expect(token?.provider, 'jpush');
    expect(token?.platform, 'android');
    expect(token?.token, 'registration-id');
  });

  test('拒绝平台与推送厂商不匹配的设备令牌', () async {
    final channel = MethodChannel('test/mismatched-device-token');
    channel.setMockMethodCallHandler((_) async => {
          'provider': 'jpush',
          'platform': 'ios',
          'environment': 'production',
          'token': 'registration-id',
        });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    expect(
        await const PushTokenProvider(
                channel: MethodChannel('test/mismatched-device-token'))
            .readDeviceToken(),
        isNull);
  });

  test('拒绝开发环境 JPush 令牌', () async {
    final channel = MethodChannel('test/jpush-development-token');
    channel.setMockMethodCallHandler((_) async => {
          'provider': 'jpush',
          'platform': 'android',
          'environment': 'development',
          'token': 'registration-id',
        });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    expect(
        await const PushTokenProvider(
                channel: MethodChannel('test/jpush-development-token'))
            .readDeviceToken(),
        isNull);
  });

  test('拒绝奇数长度的 APNs 令牌', () async {
    final channel = MethodChannel('test/odd-apns-token');
    channel.setMockMethodCallHandler((_) async => {
          'provider': 'apns',
          'platform': 'ios',
          'environment': 'production',
          'token': 'a' * 33,
        });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    expect(
        await const PushTokenProvider(
                channel: MethodChannel('test/odd-apns-token'))
            .readDeviceToken(),
        isNull);
  });

  test('退出登录时按当前安装撤销服务端推送授权', () async {
    final requests = <http.Request>[];
    final channel = MethodChannel('test/push-revoke');
    channel.setMockMethodCallHandler((_) async => {
          'grant_id': 'grant-1',
          'installation_id': 'install-1',
          'send_token': 'token-1',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        });
    addTearDown(() {
      channel.setMockMethodCallHandler(null);
    });
    final service = PushService(client: MockClient((request) async {
      requests.add(request);
      return http.Response('', 204);
    }));

    expect(
        await service.revokePlatformGrant(
            serverUrl: 'https://chat.example.com',
            sessionToken: 'session-1',
            provider: const PushTokenProvider(
                channel: MethodChannel('test/push-revoke'))),
        isTrue);
    expect(requests.single.method, 'POST');
    expect(
        requests.single.url.path, '/api/client/push/grants/install-1/revoke');
    expect(requests.single.headers['Authorization'], 'Bearer session-1');
    expect(jsonDecode(requests.single.body), {'grant_id': 'grant-1'});
  });

  test('解析服务端通知路由 success/data 响应', () async {
    final requests = <http.Request>[];
    final service = PushService(client: MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'conversation_id': 'conversation-1',
              'message_id': 'message-1',
            },
          }),
          200);
    }));

    final route = await service.resolveRoute(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'session-1',
        routeToken: 'route/token');

    expect(route.conversationId, 'conversation-1');
    expect(route.messageId, 'message-1');
    expect(requests.single.url.path, '/api/client/push/routes/resolve');
    expect(requests.single.headers['Authorization'], 'Bearer session-1');
    expect(jsonDecode(requests.single.body), {'route_token': 'route/token'});
  });

  test('通知路由响应缺少 data 字段时拒绝', () async {
    final service = PushService(
        client: MockClient((_) async =>
            http.Response(jsonEncode({'success': true, 'data': {}}), 200)));

    expect(
      () => service.resolveRoute(
          serverUrl: 'https://chat.example.com',
          sessionToken: 'session-1',
          routeToken: 'route-token'),
      throwsA(isA<FormatException>()),
    );
  });

  test('读取原生通知点击 route token 并去除空白', () async {
    final channel = MethodChannel('test/push-route-token');
    channel.setMockMethodCallHandler((call) async {
      expect(call.method, 'getPendingRoute');
      return {'route_token': '  route-token  '};
    });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    expect(
        await const PushTokenProvider(
                channel: MethodChannel('test/push-route-token'))
            .takePendingRouteToken(),
        'route-token');
  });

  test('读取本地通知携带的会话和消息路由', () async {
    final channel = MethodChannel('test/push-direct-route');
    channel.setMockMethodCallHandler((call) async {
      expect(call.method, 'getPendingRoute');
      return {
        'conversation_id': ' conversation-1 ',
        'message_id': ' message-1 ',
      };
    });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    final route = await const PushTokenProvider(
            channel: MethodChannel('test/push-direct-route'))
        .takePendingRoute();

    expect(route?.conversationId, 'conversation-1');
    expect(route?.messageId, 'message-1');
    expect(route?.routeToken, isEmpty);
  });

  test('应用前台时接收原生通知点击事件', () async {
    const channel = MethodChannel('test/push-route-opened');
    final provider = const PushTokenProvider(channel: channel);
    PendingPushRoute? opened;
    provider.setRouteOpenedHandler((route) async => opened = route);
    addTearDown(() => provider.setRouteOpenedHandler(null));

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall(
          'routeOpened',
          {'conversation_id': 'conversation-1', 'message_id': 'message-1'})),
      (_) {},
    );

    expect(opened?.conversationId, 'conversation-1');
    expect(opened?.messageId, 'message-1');
  });

  test('推送接口保留服务端业务错误消息', () async {
    final service = PushService(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'success': false,
                'error': {'code': 'push_disabled', 'message': '服务器未开启推送'},
              }),
              503,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )));

    await expectLater(
      service.resolveRoute(
          serverUrl: 'https://chat.example.com',
          sessionToken: 'session-1',
          routeToken: 'route-token'),
      throwsA(isA<PushRequestException>()
          .having((error) => error.statusCode, 'statusCode', 503)
          .having((error) => error.code, 'code', 'push_disabled')
          .having((error) => error.message, 'message', '服务器未开启推送')),
    );
  });

  test('设备令牌经 Gateway 换取授权并注册到私有 Server', () async {
    final channel = MethodChannel('test/push-device-token');
    channel.setMockMethodCallHandler((call) async {
      if (call.method == 'getDeviceToken') {
        return {
          'provider': 'apns',
          'platform': 'ios',
          'environment': 'production',
          'token': 'a' * 64,
        };
      }
      return null;
    });
    addTearDown(() => channel.setMockMethodCallHandler(null));

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'push.example.com' &&
          request.url.path == '/api/v1/installations') {
        return http.Response(
            jsonEncode({
              'installation_id': 'install-1',
              'management_token': 'manage-1'
            }),
            201);
      }
      if (request.url.host == 'push.example.com' &&
          request.url.path == '/api/v1/installations/install-1/active-grant') {
        return http.Response(
            jsonEncode({
              'grant_id': 'grant-1',
              'send_token': 'send-1',
              'expires_at': '2999-01-01T00:00:00Z',
            }),
            201);
      }
      if (request.url.host == 'chat.example.com' &&
          request.url.path == '/api/client/push/grants') {
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      }
      return http.Response('', 204);
    });
    final service = PushService(
      client: client,
      gateway: PushGatewayService(
          client: client, gatewayUrl: 'https://push.example.com'),
      registrationStore: _MemoryPushRegistrationStore(),
    );

    final registered = await service.registerPlatformGrant(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'session-1',
        platform: 'ios',
        provider: const PushTokenProvider(
            channel: MethodChannel('test/push-device-token')));

    expect(registered, isTrue);
    expect(
        requests.map((request) =>
            '${request.method} ${request.url.host}${request.url.path}'),
        [
          'POST push.example.com/api/v1/installations',
          'POST push.example.com/api/v1/installations/install-1/active-grant',
          'PUT chat.example.com/api/client/push/grants',
        ]);
    expect(jsonDecode(requests[0].body)['provider_token'], 'a' * 64);
    expect(jsonDecode(requests[2].body), {
      'expires_at': '2999-01-01T00:00:00.000Z',
      'grant_id': 'grant-1',
      'installation_id': 'install-1',
      'platform': 'ios',
      'send_token': 'send-1',
    });

    expect(
        await service.revokePlatformGrant(
            serverUrl: 'https://chat.example.com',
            sessionToken: 'session-1',
            provider: const PushTokenProvider(
                channel: MethodChannel('test/push-device-token'))),
        isTrue);
    expect(requests[3].method, 'POST');
    expect(requests[3].url.path, '/api/client/push/grants/install-1/revoke');
    expect(requests[4].method, 'DELETE');
    expect(requests[4].url.path, '/api/v1/grants/grant-1');
  });
}
