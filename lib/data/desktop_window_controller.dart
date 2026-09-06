import 'package:flutter/services.dart';

enum DesktopCloseBehavior { background, quit }

extension DesktopCloseBehaviorLabel on DesktopCloseBehavior {
  String get label => switch (this) {
        DesktopCloseBehavior.background => '在后台运行',
        DesktopCloseBehavior.quit => '退出应用',
      };
}

abstract interface class DesktopWindowController {
  Future<void> show();
  Future<void> quit();
  Future<void> setTrayReady(bool ready);
  Future<void> setCloseBehavior(DesktopCloseBehavior behavior);
}

class PlatformDesktopWindowController implements DesktopWindowController {
  const PlatformDesktopWindowController();

  static const _channel = MethodChannel('magicchat/desktop_window');

  @override
  Future<void> show() => _channel.invokeMethod<void>('show');

  @override
  Future<void> quit() => _channel.invokeMethod<void>('quit');

  @override
  Future<void> setTrayReady(bool ready) =>
      _channel.invokeMethod<void>('setTrayReady', ready);

  @override
  Future<void> setCloseBehavior(DesktopCloseBehavior behavior) =>
      _channel.invokeMethod<void>('setCloseBehavior', behavior.name);
}
