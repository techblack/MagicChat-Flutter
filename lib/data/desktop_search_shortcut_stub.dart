import 'package:flutter/foundation.dart';

import 'desktop_search_shortcut_types.dart';

class DesktopSearchShortcutController {
  DesktopSearchShortcutController({
    DesktopShortcutHotKeyBackend? hotKeyBackend,
    TargetPlatform? platform,
  });

  bool get isSupported => false;

  Future<bool> beginRecording() async => true;

  Future<bool> cancelRecording() async => true;

  Future<bool> configure(
          DesktopSearchShortcut shortcut, AsyncCallback onTriggered) async =>
      true;

  Future<void> dispose() async {}
}
