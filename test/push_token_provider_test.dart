import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/push_service.dart';
import 'package:magicchat_client/data/push_token_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
