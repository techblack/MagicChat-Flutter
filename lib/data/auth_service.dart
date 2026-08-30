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

  Future<ClientAppInfo> fetchClientInfo({required String serverUrl}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client.get(base.resolve('api/client/info'),
        headers: {'Accept': 'application/json'}).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('读取服务器登录能力失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('服务器信息响应格式不正确');
    }
    final providers = <ClientThirdPartyProvider>[];
    final rawProviders = data.containsKey('third_party_providers')
        ? data['third_party_providers']
        : data['oidc_providers'];
    if (rawProviders != null && rawProviders is! List) {
      throw const FormatException('第三方登录方式响应格式不正确');
    }
    if (rawProviders is List) {
      for (final item in rawProviders) {
        if (item is! Map<String, dynamic> ||
            item['key'] is! String ||
            item['name'] is! String ||
            (item['key'] as String).isEmpty ||
            (item['name'] as String).isEmpty) {
          throw const FormatException('第三方登录方式响应格式不正确');
        }
        providers.add(ClientThirdPartyProvider(
            key: item['key'] as String, name: item['name'] as String));
      }
    }
    return ClientAppInfo(
      emailCodeLoginEnabled: data['email_code_login_enabled'] == true,
      passwordLoginEnabled: data['password_login_enabled'] != false,
      thirdPartyProviders: providers,
    );
  }

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

class ClientAppInfo {
  const ClientAppInfo({
    required this.emailCodeLoginEnabled,
    required this.passwordLoginEnabled,
    required this.thirdPartyProviders,
  });
  final bool emailCodeLoginEnabled;
  final bool passwordLoginEnabled;
  final List<ClientThirdPartyProvider> thirdPartyProviders;
}

class ClientThirdPartyProvider {
  const ClientThirdPartyProvider({required this.key, required this.name});
  final String key;
  final String name;
}
