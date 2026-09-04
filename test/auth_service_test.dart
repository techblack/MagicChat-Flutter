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
}
