import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'http_client.dart';
import 'push_token_provider.dart';
import 'push_registration_store.dart';
import 'session_store.dart';

const pushGatewayUrl = 'https://push.jiying.chat';
const pushClientVersion =
    String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '0.3.11');
const pushGrantRenewalWindow = Duration(days: 7);

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

class PushGatewayRequestException implements Exception {
  const PushGatewayRequestException(
      {required this.statusCode, required this.message, this.code});

  final int statusCode;
  final String? code;
  final String message;

  @override
  String toString() => message;
}

class PushGatewayService {
  PushGatewayService({http.Client? client, String gatewayUrl = pushGatewayUrl})
      : _client = client ?? createMagicChatHttpClient(),
        _baseUri =
            Uri.parse(gatewayUrl.endsWith('/') ? gatewayUrl : '$gatewayUrl/');

  final http.Client _client;
  final Uri _baseUri;

  Future<({String installationId, String managementToken})>
      registerInstallation({
    required PushDeviceToken device,
    required String appVersion,
  }) async {
    final value = await _request('POST', 'api/v1/installations', body: {
      'app_version': appVersion,
      'environment': device.environment,
      'platform': device.platform,
      'provider': device.provider,
      'provider_token': device.token,
    });
    if (value is! Map<String, dynamic> ||
        value['installation_id'] is! String ||
        (value['installation_id'] as String).isEmpty ||
        value['management_token'] is! String ||
        (value['management_token'] as String).isEmpty) {
      throw const FormatException('推送安装注册响应格式不正确');
    }
    return (
      installationId: value['installation_id'] as String,
      managementToken: value['management_token'] as String
    );
  }

  Future<void> updateProviderToken({
    required String installationId,
    required String managementToken,
    required String appVersion,
    required String providerToken,
  }) async {
    await _request('PUT',
        'api/v1/installations/${Uri.encodeComponent(installationId)}/provider-token',
        authorization: managementToken,
        authorizationScheme: 'Installation',
        body: {'app_version': appVersion, 'provider_token': providerToken});
  }

  Future<({String grantId, String sendToken, DateTime expiresAt})>
      createActiveGrant({
    required String installationId,
    required String managementToken,
  }) async {
    final value = await _request('POST',
        'api/v1/installations/${Uri.encodeComponent(installationId)}/active-grant',
        authorization: managementToken, authorizationScheme: 'Installation');
    return _grantFromJson(value);
  }

  Future<DateTime> renewGrant(
      {required String grantId, required String managementToken}) async {
    final value = await _request(
        'POST', 'api/v1/grants/${Uri.encodeComponent(grantId)}/renew',
        authorization: managementToken, authorizationScheme: 'Installation');
    if (value is! Map<String, dynamic> || value['expires_at'] is! String) {
      throw const FormatException('推送授权续期响应格式不正确');
    }
    final expiresAt = DateTime.tryParse(value['expires_at'] as String)?.toUtc();
    if (expiresAt == null) {
      throw const FormatException('推送授权续期响应格式不正确');
    }
    return expiresAt;
  }

  Future<void> revokeGrant(
      {required String grantId, required String managementToken}) async {
    await _request('DELETE', 'api/v1/grants/${Uri.encodeComponent(grantId)}',
        authorization: managementToken, authorizationScheme: 'Installation');
  }

  ({String grantId, String sendToken, DateTime expiresAt}) _grantFromJson(
      dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['grant_id'] is! String ||
        (value['grant_id'] as String).isEmpty ||
        value['send_token'] is! String ||
        (value['send_token'] as String).isEmpty ||
        value['expires_at'] is! String) {
      throw const FormatException('推送授权响应格式不正确');
    }
    final expiresAt = DateTime.tryParse(value['expires_at'] as String)?.toUtc();
    if (expiresAt == null) {
      throw const FormatException('推送授权响应格式不正确');
    }
    return (
      grantId: value['grant_id'] as String,
      sendToken: value['send_token'] as String,
      expiresAt: expiresAt
    );
  }

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? body,
      String? authorization,
      String? authorizationScheme}) async {
    final request = http.Request(method, _baseUri.resolve(path))
      ..headers.addAll({
        'Accept': 'application/json',
        if (authorization != null)
          'Authorization': '${authorizationScheme ?? 'Bearer'} $authorization',
        if (body != null) 'Content-Type': 'application/json',
      })
      ..body = body == null ? '' : jsonEncode(body);
    final response =
        await _client.send(request).timeout(PushService.requestTimeout);
    final text = await response.stream.bytesToString();
    dynamic value;
    if (text.isNotEmpty) {
      try {
        value = jsonDecode(text);
      } catch (_) {
        throw const FormatException('推送网关响应格式不正确');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _error(response.statusCode, value);
    }
    return value;
  }

  PushGatewayRequestException _error(int statusCode, dynamic value) {
    final error = value is Map<String, dynamic> ? value['error'] : null;
    final code = error is Map<String, dynamic> && error['code'] is String
        ? error['code'] as String
        : null;
    final message = error is Map<String, dynamic> && error['message'] is String
        ? (error['message'] as String).trim()
        : '';
    return PushGatewayRequestException(
        statusCode: statusCode,
        code: code,
        message: message.isEmpty ? '推送网关请求失败（HTTP $statusCode）' : message);
  }
}

/// 私有 Server 推送授权生命周期。设备厂商 Token 由各平台插件提供，不写入普通配置。
class PushService {
  static const requestTimeout = Duration(seconds: 30);
  PushService({
    http.Client? client,
    PushGatewayService? gateway,
    PushRegistrationStore? registrationStore,
  })  : _client = client ?? createMagicChatHttpClient(),
        _gateway = gateway ?? PushGatewayService(client: client),
        _registrationStore = registrationStore ?? const PushRegistrationStore();
  final http.Client _client;
  final PushGatewayService _gateway;
  final PushRegistrationStore _registrationStore;

  Map<String, String> _sessionHeaders(String token) =>
      token == SessionStore.cookieSessionToken
          ? const {}
          : {'Authorization': 'Bearer $token'};

  Future<bool> registerPlatformGrant({
    required String serverUrl,
    required String sessionToken,
    required String platform,
    String appVersion = pushClientVersion,
    PushTokenProvider provider = const PushTokenProvider(),
  }) async {
    final device = await provider.readDeviceToken();
    if (device != null) {
      final grant =
          await _ensureGatewayGrant(device, appVersion, serverUrl: serverUrl);
      await registerGrant(
          serverUrl: serverUrl,
          sessionToken: sessionToken,
          platform: platform,
          grant: grant);
      return true;
    }
    final storedGrant = await _registrationStore.readGrant();
    if (storedGrant != null && storedGrant.serverUrl == serverUrl) {
      await registerGrant(
          serverUrl: serverUrl,
          sessionToken: sessionToken,
          platform: platform,
          grant: PushGrant(
              grantId: storedGrant.grantId,
              installationId: storedGrant.installationId,
              sendToken: storedGrant.sendToken,
              expiresAt: storedGrant.expiresAt));
      return true;
    }
    // 兼容尚未升级的原生桥接：旧桥直接返回已签发的 grant。
    final legacyGrant = await provider.readGrant();
    if (legacyGrant == null) return false;
    await registerGrant(
        serverUrl: serverUrl,
        sessionToken: sessionToken,
        platform: platform,
        grant: PushGrant(
            grantId: legacyGrant.grantId,
            installationId: legacyGrant.installationId,
            sendToken: legacyGrant.sendToken,
            expiresAt: legacyGrant.expiresAt));
    return true;
  }

  Future<PushGrant> _ensureGatewayGrant(
      PushDeviceToken device, String appVersion,
      {required String serverUrl}) async {
    var installation = await _registrationStore.readInstallation();
    final mismatched = installation == null ||
        installation.provider != device.provider ||
        installation.platform != device.platform ||
        installation.environment != device.environment;
    if (mismatched) {
      installation = await _createInstallation(device, appVersion);
      await _registrationStore.clearGrant();
    } else if (installation.providerToken != device.token ||
        installation.appVersion != appVersion) {
      try {
        await _gateway.updateProviderToken(
            installationId: installation.installationId,
            managementToken: installation.managementToken,
            appVersion: appVersion,
            providerToken: device.token);
        installation = StoredPushInstallation(
            installationId: installation.installationId,
            managementToken: installation.managementToken,
            provider: installation.provider,
            platform: installation.platform,
            environment: installation.environment,
            providerToken: device.token,
            appVersion: appVersion);
        await _registrationStore.writeInstallation(installation);
      } on PushGatewayRequestException catch (error) {
        if (!_gatewayCredentialIsInvalid(error)) rethrow;
        installation = await _createInstallation(device, appVersion);
        await _registrationStore.clearGrant();
      }
    }

    var grant = await _registrationStore.readGrant();
    if (grant == null ||
        grant.installationId != installation.installationId ||
        grant.serverUrl != serverUrl) {
      grant = await _createGrant(installation, serverUrl);
    } else if (grant.expiresAt
        .isBefore(DateTime.now().toUtc().add(pushGrantRenewalWindow))) {
      try {
        final expiresAt = await _gateway.renewGrant(
            grantId: grant.grantId,
            managementToken: installation.managementToken);
        grant = StoredPushGrant(
            grantId: grant.grantId,
            sendToken: grant.sendToken,
            expiresAt: expiresAt,
            installationId: installation.installationId,
            serverUrl: serverUrl);
        await _registrationStore.writeGrant(grant);
      } on PushGatewayRequestException catch (error) {
        if (!_gatewayCredentialIsInvalid(error)) rethrow;
        grant = await _createGrant(installation, serverUrl);
      }
    }
    return PushGrant(
        grantId: grant.grantId,
        installationId: installation.installationId,
        sendToken: grant.sendToken,
        expiresAt: grant.expiresAt);
  }

  Future<StoredPushInstallation> _createInstallation(
      PushDeviceToken device, String appVersion) async {
    final value = await _gateway.registerInstallation(
        device: device, appVersion: appVersion);
    final installation = StoredPushInstallation(
        installationId: value.installationId,
        managementToken: value.managementToken,
        provider: device.provider,
        platform: device.platform,
        environment: device.environment,
        providerToken: device.token,
        appVersion: appVersion);
    await _registrationStore.writeInstallation(installation);
    return installation;
  }

  Future<StoredPushGrant> _createGrant(
      StoredPushInstallation installation, String serverUrl) async {
    final value = await _gateway.createActiveGrant(
        installationId: installation.installationId,
        managementToken: installation.managementToken);
    final grant = StoredPushGrant(
        grantId: value.grantId,
        sendToken: value.sendToken,
        expiresAt: value.expiresAt,
        installationId: installation.installationId,
        serverUrl: serverUrl);
    await _registrationStore.writeGrant(grant);
    return grant;
  }

  bool _gatewayCredentialIsInvalid(PushGatewayRequestException error) =>
      error.statusCode == 401 ||
      error.statusCode == 404 ||
      error.statusCode == 410;

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
    final storedGrant = await _registrationStore.readGrant();
    final installation = await _registrationStore.readInstallation();
    final grant = storedGrant == null ? await provider.readGrant() : null;
    if (storedGrant == null && grant == null) return false;
    final installationId = storedGrant?.installationId ?? grant!.installationId;
    final grantId = storedGrant?.grantId ?? grant!.grantId;
    Object? failure;
    try {
      if (storedGrant == null || storedGrant.serverUrl == serverUrl) {
        await revokeGrant(
            serverUrl: serverUrl,
            sessionToken: sessionToken,
            installationId: installationId,
            grantId: grantId);
      }
    } catch (error) {
      failure = error;
    }
    if (storedGrant != null &&
        installation != null &&
        installation.installationId == storedGrant.installationId) {
      try {
        await _gateway.revokeGrant(
            grantId: storedGrant.grantId,
            managementToken: installation.managementToken);
      } catch (error) {
        failure ??= error;
      }
    }
    await _registrationStore.clearGrant();
    if (failure != null) throw failure;
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
