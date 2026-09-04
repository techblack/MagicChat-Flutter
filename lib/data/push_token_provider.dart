import 'package:flutter/services.dart';

/// 原生 APNs/JPush 插件的最小桥接契约。
/// 插件返回 null 表示当前平台/环境暂不可用，调用方应继续正常运行。
class PushTokenProvider {
  const PushTokenProvider(
      {MethodChannel channel = const MethodChannel('magicchat/push')})
      : _channel = channel;
  final MethodChannel _channel;

  Future<PushTokenGrant?> readGrant() async {
    try {
      final value = await _channel.invokeMethod<Object?>('getGrant');
      if (value is! Map) return null;
      final grantId = value['grant_id'];
      final installationId = value['installation_id'];
      final sendToken = value['send_token'];
      final expiresAt = value['expires_at'];
      if (grantId is! String ||
          installationId is! String ||
          sendToken is! String ||
          expiresAt is! String) return null;
      final expiry = DateTime.tryParse(expiresAt);
      if (expiry == null || expiry.isBefore(DateTime.now().toUtc()))
        return null;
      return PushTokenGrant(
          grantId: grantId,
          installationId: installationId,
          sendToken: sendToken,
          expiresAt: expiry);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 读取平台原生设备令牌。令牌只用于推送网关注册，不包含账号或消息内容。
  /// 原生适配器缺失、权限/系统服务不可用或响应格式不正确时返回 null。
  Future<PushDeviceToken?> readDeviceToken() async {
    try {
      final value = await _channel.invokeMethod<Object?>('getDeviceToken');
      if (value is! Map) return null;
      final provider = value['provider'];
      final platform = value['platform'];
      final environment = value['environment'];
      final token = value['token'];
      if (provider is! String ||
          platform is! String ||
          environment is! String ||
          token is! String) return null;
      final normalizedToken = token.trim();
      if (normalizedToken.isEmpty ||
          (provider != 'apns' && provider != 'jpush') ||
          (platform != 'ios' && platform != 'android') ||
          (provider == 'apns' && platform != 'ios') ||
          (provider == 'jpush' && platform != 'android') ||
          (provider == 'apns' &&
              (normalizedToken.length < 32 ||
                  normalizedToken.length.isOdd ||
                  !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalizedToken))) ||
          (provider == 'jpush' && normalizedToken.length < 8) ||
          (provider == 'jpush' && environment != 'production') ||
          (environment != 'development' && environment != 'production')) {
        return null;
      }
      return PushDeviceToken(
          provider: provider,
          platform: platform,
          environment: environment,
          token: normalizedToken);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 消费原生通知点击携带的一次性 route token。
  Future<String?> takePendingRouteToken() async {
    try {
      final value =
          await _channel.invokeMethod<Object?>('getPendingRouteToken');
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

class PushDeviceToken {
  const PushDeviceToken(
      {required this.provider,
      required this.platform,
      required this.environment,
      required this.token});
  final String provider;
  final String platform;
  final String environment;
  final String token;
}

class PushTokenGrant {
  const PushTokenGrant(
      {required this.grantId,
      required this.installationId,
      required this.sendToken,
      required this.expiresAt});
  final String grantId;
  final String installationId;
  final String sendToken;
  final DateTime expiresAt;
}
