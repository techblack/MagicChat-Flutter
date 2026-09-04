import 'package:flutter/services.dart';

/// 同步系统应用图标/Dock 的未读角标。
///
/// 不支持角标的平台会静默降级，应用内导航和会话列表仍显示同一未读数。
class AppBadgeService {
  const AppBadgeService(
      {MethodChannel channel = const MethodChannel('magicchat/app_badge')})
      : _channel = channel;

  final MethodChannel _channel;

  Future<void> setCount(int count) async {
    try {
      await _channel.invokeMethod<void>('setCount', {
        'count': count < 0 ? 0 : count,
      });
    } on MissingPluginException {
      // Web/Linux/未实现系统角标的平台继续使用 Flutter 内的未读红点。
    } on PlatformException {
      // 系统或桌面环境拒绝角标时不影响聊天功能。
    }
  }
}
