import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'http_client.dart';
import 'session_store.dart';

class AuthService {
  static const requestTimeout = Duration(seconds: 30);
  AuthService({http.Client? client, SessionStore? sessions})
      : _client = client ?? createMagicChatHttpClient(),
        _sessions = sessions ?? const SessionStore();
  final http.Client _client;
  final SessionStore _sessions;

  Future<void> requestEmailCode(
      {required String serverUrl, required String email}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .post(base.resolve('api/client/auth/email-code/request'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'email': email}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('验证码发送失败（HTTP ${response.statusCode}）');
    }
  }

  Future<void> loginWithEmailCode(
      {required String serverUrl,
      required String email,
      required String code}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .post(base.resolve('api/client/auth/email-code/login'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'X-Dianbao-Mobile-Session': '1'
            },
            body: jsonEncode({'email': email, 'code': code}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('验证码登录失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    final session =
        data is Map<String, dynamic> ? data['mobile_session'] : null;
    final token = session is Map<String, dynamic> ? session['token'] : null;
    if (token is! String || token.isEmpty) {
      if (kIsWeb) {
        await _sessions.writeToken(SessionStore.cookieSessionToken);
        return;
      }
      throw const FormatException('登录响应缺少会话凭据');
    }
    await _sessions.writeToken(token);
  }

  Future<void> login(
      {required String serverUrl,
      required String email,
      required String password}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .post(base.resolve('api/client/auth/login'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'email': email, 'password': password}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('登录失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    final session =
        data is Map<String, dynamic> ? data['mobile_session'] : null;
    final token = session is Map<String, dynamic> ? session['token'] : null;
    if (token is! String || token.isEmpty) {
      if (kIsWeb) {
        await _sessions.writeToken(SessionStore.cookieSessionToken);
        return;
      }
      throw const FormatException('登录响应缺少会话凭据');
    }
    await _sessions.writeToken(token);
  }

  Future<void> logout({required String serverUrl}) async {
    final token = await _sessions.readToken();
    if (token != null) {
      final base =
          Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
      final headers = token == SessionStore.cookieSessionToken
          ? <String, String>{}
          : {'Authorization': 'Bearer $token'};
      await _client
          .post(base.resolve('api/client/auth/logout'), headers: headers)
          .timeout(requestTimeout);
    }
    await _sessions.clear();
  }
}
