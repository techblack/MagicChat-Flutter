import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_window_title_platform_interface.dart';
import 'desktop_window_controller.dart';

AppWindowTitlePlatform createAppWindowTitlePlatform({
  DesktopWindowController? desktopWindowController,
}) =>
    _NativeAppWindowTitlePlatform(
      desktopWindowController ?? const PlatformDesktopWindowController(),
    );

class _NativeAppWindowTitlePlatform implements AppWindowTitlePlatform {
  const _NativeAppWindowTitlePlatform(this._windowController);

  final DesktopWindowController _windowController;

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Future<void> update({required String title, required bool alert}) async {
    if (!_supported) return;
    try {
      await _windowController.setTitle(title);
    } on MissingPluginException {
      // Runner 未实现标题桥接时保留系统默认标题。
    } on PlatformException {
      // 标题更新不影响主界面继续运行。
    }
  }

  @override
  Future<void> dispose() async {}
}
