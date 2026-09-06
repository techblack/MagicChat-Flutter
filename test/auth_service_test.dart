import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/auth_service.dart';
import 'package:magicchat_client/data/session_store.dart';

class _MemorySessionStore extends SessionStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(jsonEncode(body), statusCode,
        headers: {'content-type': 'application/json'});

void main() {
  test('服务器地址补全 HTTPS 并保留部署子路径', () {
    expect(normalizeServerUrl(' chat.example.com/base/ '),
        'https://chat.example.com/base');
    expect(
        normalizeServerUrl('http://localhost:8080/'), 'http://localhost:8080');
    expect(() => normalizeServerUrl('ftp://chat.example.com'),
        throwsFormatException);
    expect(() => normalizeServerUrl('https://chat.example.com/?token=x'),
        throwsFormatException);
  });

  test('解析服务端第三方登录方式', () async {
    final service = AuthService(
        client: MockClient((_) async => _jsonResponse({
              'data': {
                'app_name': '星环协作',
                'organization_name': '长亭科技',
                'authenticated': false,
                'password_login_enabled': true,
                'email_code_login_enabled': false,
                'third_party_providers': [
                  {'key': 'oidc', 'name': '企业 SSO'}
                ],
              }
            })));

    final info =
        await service.fetchClientInfo(serverUrl: 'https://chat.example.com');

    expect(info.thirdPartyProviders.single.key, 'oidc');
    expect(info.thirdPartyProviders.single.name, '企业 SSO');
    expect(info.appName, '星环协作');
    expect(info.organizationName, '长亭科技');
    expect(info.authenticated, isFalse);
  });

  test('服务器品牌字段缺失时拒绝响应', () async {
    final service = AuthService(
        client: MockClient((_) async => _jsonResponse({
              'data': {
                'password_login_enabled': true,
                'email_code_login_enabled': false,
              }
            })));

    expect(service.fetchClientInfo(serverUrl: 'https://chat.example.com'),
        throwsFormatException);
  });

  test('密码登录声明 Native Session 能力并保存返回 Token', () async {
    late http.Request captured;
    final sessions = _MemorySessionStore();
    final service = AuthService(
      sessions: sessions,
      client: MockClient((request) async {
        captured = request;
        return _jsonResponse({
          'success': true,
          'data': {
            'mobile_session': {
              'token': 'mobile-token',
              'expires_at': '2999-01-01T00:00:00Z',
            },
          },
        });
      }),
    );

    await service.login(
        serverUrl: 'chat.example.com',
        email: 'alice@example.com',
        password: 'secret');

    expect(captured.url.toString(),
        'https://chat.example.com/api/client/auth/login');
    expect(captured.headers[mobileSessionHeader], mobileSessionVersion);
    expect(jsonDecode(captured.body), {
      'email': 'alice@example.com',
      'password': 'secret',
    });
    expect(sessions.token, 'mobile-token');
  });

  test('验证码发送结果保留有效期和重试间隔', () async {
    final service = AuthService(
      client: MockClient((request) async {
        expect(request.url.path, '/base/api/client/auth/email-code/request');
        return _jsonResponse({
          'success': true,
          'data': {
            'expires_in_seconds': 600,
            'retry_after_seconds': 60,
          },
        });
      }),
    );

    final result = await service.requestEmailCode(
        serverUrl: 'https://chat.example.com/base/',
        email: 'alice@example.com');

    expect(result.expiresInSeconds, 600);
    expect(result.retryAfterSeconds, 60);
  });

  test('认证错误优先显示服务端消息', () async {
    final service = AuthService(
      client: MockClient((_) async => _jsonResponse({
            'success': false,
            'error': {'code': 'invalid_credentials', 'message': '邮箱或密码错误'},
          }, statusCode: 401)),
    );

    await expectLater(
      service.login(
          serverUrl: 'https://chat.example.com',
          email: 'alice@example.com',
          password: 'wrong'),
      throwsA(isA<AuthRequestException>()
          .having((error) => error.message, 'message', '邮箱或密码错误')),
    );
  });

  test('Native 登录拒绝已过期会话', () async {
    final service = AuthService(
      sessions: _MemorySessionStore(),
      client: MockClient((_) async => _jsonResponse({
            'success': true,
            'data': {
              'mobile_session': {
                'token': 'expired-token',
                'expires_at': '2000-01-01T00:00:00Z',
              },
            },
          })),
    );

    await expectLater(
      service.login(
          serverUrl: 'https://chat.example.com',
          email: 'alice@example.com',
          password: 'secret'),
      throwsA(isA<FormatException>()
          .having((error) => error.message, 'message', contains('会话已过期'))),
    );
  });

  test('远端注销失败仍清空本地会话', () async {
    final sessions = _MemorySessionStore()..token = 'session-token';
    final service = AuthService(
      sessions: sessions,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    await expectLater(
      service.logout(serverUrl: 'https://chat.example.com'),
      throwsA(isA<http.ClientException>()),
    );
    expect(sessions.token, isNull);
  });

  test('注销验证码只针对当前认证账号发送并解析重试时间', () async {
    final sessions = _MemorySessionStore()..token = 'session-token';
    late http.Request captured;
    final service = AuthService(
      sessions: sessions,
      client: MockClient((request) async {
        captured = request;
        return _jsonResponse({
          'success': true,
          'data': {
            'expires_in_seconds': 900,
            'retry_after_seconds': 60,
          },
        });
      }),
    );

    final result = await service.requestAccountDeactivationCode(
        serverUrl: 'https://chat.example.com/base');

    expect(captured.url.path, '/base/api/client/me/deactivation/code');
    expect(captured.headers['Authorization'], 'Bearer session-token');
    expect(captured.body, isEmpty);
    expect(result.expiresInSeconds, 900);
    expect(result.retryAfterSeconds, 60);
  });

  test('注销账号提交规范化验证码并保留明确错误码', () async {
    final sessions = _MemorySessionStore()..token = 'session-token';
    final requests = <http.Request>[];
    final service = AuthService(
      sessions: sessions,
      client: MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return _jsonResponse({
            'success': false,
            'error': {'code': 'invalid_code', 'message': '验证码错误'},
          }, statusCode: 401);
        }
        return _jsonResponse({'success': true, 'data': {}});
      }),
    );

    await expectLater(
      service.deactivateAccount(
          serverUrl: 'https://chat.example.com', code: '12345678'),
      throwsA(isA<AuthRequestException>()
          .having((error) => error.code, 'code', 'invalid_code')
          .having((error) => error.statusCode, 'status', 401)
          .having(isSafeAccountDeactivationRejection, 'safe rejection', true)),
    );
    expect(sessions.token, 'session-token');

    await service.deactivateAccount(
        serverUrl: 'https://chat.example.com', code: '12 34-5678');
    expect(requests.last.url.path, '/api/client/me/deactivation');
    expect(requests.last.headers['Content-Type'], 'application/json');
    expect(jsonDecode(requests.last.body), {'code': '12345678'});
  });

  test('注销验证码仅保留前 8 位数字', () {
    expect(normalizeAccountDeactivationCode('12ab 3456-789'), '12345678');
    expect(normalizeAccountDeactivationCode('abc'), isEmpty);
  });
}
