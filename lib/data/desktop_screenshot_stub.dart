import 'package:flutter/foundation.dart';

import 'desktop_screenshot_types.dart';

class DesktopScreenshotController {
  DesktopScreenshotController({
    DesktopScreenshotCaptureBackend? captureBackend,
    DesktopScreenshotHotKeyBackend? hotKeyBackend,
    TargetPlatform? platform,
    Future<String> Function()? temporaryDirectoryPath,
  });

  static const maxImageBytes = desktopScreenshotMaxImageBytes;

  bool get isSupported => false;

  Future<bool> configure(DesktopScreenshotShortcut shortcut,
          AsyncCallback onTriggered) async =>
      true;

  Future<CapturedScreenshot?> capture(DesktopScreenshotMode mode) async => null;

  Future<void> openPermissionSettings() async {}

  Future<void> dispose() async {}
}
