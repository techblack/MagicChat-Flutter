import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/push_service.dart';
import 'package:magicchat_client/data/push_token_provider.dart';

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
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/client/push/grants/install-1');
    expect(requests.single.headers['Authorization'], 'Bearer session-1');
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
    expect(requests.single.url.path, '/api/client/push/routes/route%2Ftoken');
    expect(requests.single.headers['Authorization'], 'Bearer session-1');
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
}
