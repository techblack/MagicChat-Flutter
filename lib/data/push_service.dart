import 'dart:convert';
import 'package:http/http.dart' as http;
import 'http_client.dart';
import 'push_token_provider.dart';
import 'session_store.dart';

class PushGrant {
  const PushGrant(
      {required this.grantId,
      required this.installationId,
      required this.sendToken,
      required this.expiresAt});
  final String grantId;
  final String installationId;
  final String sendToken;
  final DateTime expiresAt;
}

/// 私有 Server 推送授权生命周期。设备厂商 Token 由各平台插件提供，不写入普通配置。
class PushService {
  static const requestTimeout = Duration(seconds: 30);
  PushService({http.Client? client})
      : _client = client ?? createMagicChatHttpClient();
  final http.Client _client;

  Map<String, String> _sessionHeaders(String token) =>
      token == SessionStore.cookieSessionToken
          ? const {}
          : {'Authorization': 'Bearer $token'};

  Future<bool> registerPlatformGrant({
    required String serverUrl,
    required String sessionToken,
    required String platform,
    PushTokenProvider provider = const PushTokenProvider(),
  }) async {
    final grant = await provider.readGrant();
    if (grant == null) return false;
    await registerGrant(
        serverUrl: serverUrl,
        sessionToken: sessionToken,
        platform: platform,
        grant: PushGrant(
            grantId: grant.grantId,
            installationId: grant.installationId,
            sendToken: grant.sendToken,
            expiresAt: grant.expiresAt));
    return true;
  }

  Future<void> registerGrant(
      {required String serverUrl,
      required String sessionToken,
      required PushGrant grant,
      required String platform}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .put(base.resolve('api/client/push/grants'),
            headers: {
              ..._sessionHeaders(sessionToken),
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'expires_at': grant.expiresAt.toUtc().toIso8601String(),
              'grant_id': grant.grantId,
              'installation_id': grant.installationId,
              'platform': platform,
              'send_token': grant.sendToken
            }))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('注册推送失败（HTTP ${response.statusCode}）');
    }
  }

  /// 撤销当前平台插件暴露的授权，返回是否找到可撤销的授权。
  /// 平台没有推送适配器或授权已不可用时保持幂等，无需阻断登录生命周期。
  Future<bool> revokePlatformGrant({
    required String serverUrl,
    required String sessionToken,
    PushTokenProvider provider = const PushTokenProvider(),
  }) async {
    final grant = await provider.readGrant();
    if (grant == null) return false;
    await revokeGrant(
        serverUrl: serverUrl,
        sessionToken: sessionToken,
        installationId: grant.installationId);
    return true;
  }

  Future<void> revokeGrant(
      {required String serverUrl,
      required String sessionToken,
      required String installationId}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .delete(
            base.resolve(
                'api/client/push/grants/${Uri.encodeComponent(installationId)}'),
            headers: _sessionHeaders(sessionToken))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('撤销推送失败（HTTP ${response.statusCode}）');
    }
  }

  Future<({String conversationId, String messageId})> resolveRoute(
      {required String serverUrl,
      required String sessionToken,
      required String routeToken}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .get(
            base.resolve(
                'api/client/push/routes/${Uri.encodeComponent(routeToken)}'),
            headers: _sessionHeaders(sessionToken))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('打开通知失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    // 客户端接口的成功响应使用 `{success, data}` 包装；滚动升级期间仍兼容
    // 直接返回路由对象的旧网关。
    final value = decoded is Map<String, dynamic> &&
            decoded['data'] is Map<String, dynamic>
        ? decoded['data'] as Map<String, dynamic>
        : decoded;
    if (value is! Map<String, dynamic> ||
        value['conversation_id'] is! String ||
        value['message_id'] is! String) {
      throw const FormatException('通知路由响应格式不正确');
    }
    return (
      conversationId: value['conversation_id'] as String,
      messageId: value['message_id'] as String
    );
  }
}
