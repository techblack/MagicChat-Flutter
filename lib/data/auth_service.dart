import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'http_client.dart';
import 'session_store.dart';

const mobileSessionHeader = 'X-Dianbao-Mobile-Session';
const mobileSessionVersion = '1';

String normalizeServerUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('请输入服务器地址');
  }
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('请输入有效的 HTTP(S) 服务器地址');
  }
  final normalizedPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri.replace(path: normalizedPath).toString();
}

class AuthRequestException implements Exception {
  const AuthRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  static const requestTimeout = Duration(seconds: 15);
  AuthService({http.Client? client, SessionStore? sessions})
      : _client = client ?? createMagicChatHttpClient(),
        _sessions = sessions ?? const SessionStore();
  final http.Client _client;
  final SessionStore _sessions;

  Future<ClientAppInfo> fetchClientInfo({required String serverUrl}) async {
    final base = _baseUri(serverUrl);
    final response = await _client.get(base.resolve('api/client/info'),
        headers: {'Accept': 'application/json'}).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _responseError(response, '读取服务器登录能力失败');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['success'] == false) {
      throw _responseError(response, '读取服务器登录能力失败');
    }
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

  Future<EmailCodeRequestResult> requestEmailCode(
      {required String serverUrl, required String email}) async {
    final base = _baseUri(serverUrl);
    final response = await _client
        .post(base.resolve('api/client/auth/email-code/request'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'email': email}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _responseError(response, '验证码发送失败');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['success'] == false) {
      throw _responseError(response, '验证码发送失败');
    }
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    final expiresIn =
        data is Map<String, dynamic> ? data['expires_in_seconds'] : null;
    final retryAfter =
        data is Map<String, dynamic> ? data['retry_after_seconds'] : null;
    if (expiresIn is! int ||
        expiresIn <= 0 ||
        retryAfter is! int ||
        retryAfter < 0) {
      throw const FormatException('验证码发送响应格式不正确');
    }
    return EmailCodeRequestResult(
        expiresInSeconds: expiresIn, retryAfterSeconds: retryAfter);
  }

  Future<void> loginWithEmailCode(
      {required String serverUrl,
      required String email,
      required String code}) async {
    final base = _baseUri(serverUrl);
    final response = await _client
        .post(base.resolve('api/client/auth/email-code/login'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              mobileSessionHeader: mobileSessionVersion,
            },
            body: jsonEncode({'email': email, 'code': code}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _responseError(response, '验证码登录失败');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['success'] == false) {
      throw _responseError(response, '验证码登录失败');
    }
    await _storeLoginSession(decoded);
  }

  Future<void> login(
      {required String serverUrl,
      required String email,
      required String password}) async {
    final base = _baseUri(serverUrl);
    final response = await _client
        .post(base.resolve('api/client/auth/login'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              mobileSessionHeader: mobileSessionVersion,
            },
            body: jsonEncode({'email': email, 'password': password}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _responseError(response, '登录失败');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['success'] == false) {
      throw _responseError(response, '登录失败');
    }
    await _storeLoginSession(decoded);
  }

  Future<void> _storeLoginSession(Object? decoded) async {
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
    final expiresAt =
        session is Map<String, dynamic> ? session['expires_at'] : null;
    final expiry =
        expiresAt is String ? DateTime.tryParse(expiresAt)?.toUtc() : null;
    if (expiry == null) {
      throw const FormatException('登录响应的会话有效期不正确');
    }
    if (!expiry.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('服务器返回的会话已过期，请重新登录');
    }
    await _sessions.writeToken(token);
  }

  Future<void> logout({required String serverUrl}) async {
    try {
      final token = await _sessions.readToken();
      if (token != null) {
        final base = _baseUri(serverUrl);
        final headers = token == SessionStore.cookieSessionToken
            ? <String, String>{}
            : {'Authorization': 'Bearer $token'};
        final response = await _client
            .post(base.resolve('api/client/auth/logout'), headers: headers)
            .timeout(requestTimeout);
        if ((response.statusCode < 200 || response.statusCode >= 300) &&
            response.statusCode != 401) {
          throw _responseError(response, '退出登录失败');
        }
      }
    } finally {
      await _sessions.clear();
    }
  }

  Uri _baseUri(String serverUrl) =>
      Uri.parse('${normalizeServerUrl(serverUrl)}/');

  AuthRequestException _responseError(
      http.Response response, String fallbackMessage) {
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final message = error is Map<String, dynamic> ? error['message'] : null;
      if (message is String && message.trim().isNotEmpty) {
        return AuthRequestException(message.trim());
      }
    } catch (_) {
      // 非 JSON 错误响应使用带状态码的通用消息。
    }
    return AuthRequestException(
        '$fallbackMessage（HTTP ${response.statusCode}）');
  }
}

class EmailCodeRequestResult {
  const EmailCodeRequestResult({
    required this.expiresInSeconds,
    required this.retryAfterSeconds,
  });

  final int expiresInSeconds;
  final int retryAfterSeconds;
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
