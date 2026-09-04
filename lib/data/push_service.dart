import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'http_client.dart';
import 'push_token_provider.dart';
import 'session_store.dart';

String pushPlatformName(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    default:
      return platform.name;
  }
}

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

class PushRequestException implements Exception {
  const PushRequestException(
      {required this.statusCode, required this.message, this.code});

  final int statusCode;
  final String? code;
  final String message;

  @override
  String toString() => message;
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
      throw _requestError(response, '注册推送失败');
    }
    _throwIfBusinessFailure(response, '注册推送失败');
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
        installationId: grant.installationId,
        grantId: grant.grantId);
    return true;
  }

  Future<void> revokeGrant(
      {required String serverUrl,
      required String sessionToken,
      required String installationId,
      required String grantId}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .post(
            base.resolve(
                'api/client/push/grants/${Uri.encodeComponent(installationId)}/revoke'),
            headers: {
              ..._sessionHeaders(sessionToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'grant_id': grantId}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _requestError(response, '撤销推送失败');
    }
    _throwIfBusinessFailure(response, '撤销推送失败');
  }

  Future<({String conversationId, String messageId})> resolveRoute(
      {required String serverUrl,
      required String sessionToken,
      required String routeToken}) async {
    final base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');
    final response = await _client
        .post(base.resolve('api/client/push/routes/resolve'),
            headers: {
              ..._sessionHeaders(sessionToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'route_token': routeToken}))
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _requestError(response, '打开通知失败');
    }
    _throwIfBusinessFailure(response, '打开通知失败');
    final decoded = jsonDecode(response.body);
    // 客户端接口的成功响应使用 `{success, data}` 包装；滚动升级期间仍兼容
    // 直接返回路由对象的旧网关响应体。
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

  void _throwIfBusinessFailure(http.Response response, String fallbackMessage) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic> && value['success'] == false) {
        throw _requestError(response, fallbackMessage);
      }
    } on PushRequestException {
      rethrow;
    } catch (_) {
      // 非 JSON 成功响应由具体 API 的格式校验处理。
    }
  }

  PushRequestException _requestError(
      http.Response response, String fallbackMessage) {
    String? code;
    String? message;
    try {
      final value = jsonDecode(response.body);
      final error = value is Map<String, dynamic> ? value['error'] : null;
      if (error is Map<String, dynamic>) {
        code = error['code'] is String ? error['code'] as String : null;
        message =
            error['message'] is String ? error['message'] as String : null;
      }
    } catch (_) {
      // 非 JSON 错误响应回退到状态信息。
    }
    return PushRequestException(
        statusCode: response.statusCode,
        code: code,
        message: message?.trim().isNotEmpty == true
            ? message!.trim()
            : '$fallbackMessage（HTTP ${response.statusCode}）');
  }
}
