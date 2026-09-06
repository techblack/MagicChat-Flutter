import 'package:flutter/services.dart';

abstract interface class DesktopWindowController {
  Future<void> show();
  Future<void> quit();
  Future<void> setTrayReady(bool ready);
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
}
