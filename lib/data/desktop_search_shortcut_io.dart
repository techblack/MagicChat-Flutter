import 'package:flutter/foundation.dart';

import 'desktop_search_shortcut_types.dart';
import 'desktop_shortcut_io.dart';

class DesktopSearchShortcutController {
  DesktopSearchShortcutController({
    DesktopShortcutHotKeyBackend? hotKeyBackend,
    TargetPlatform? platform,
  })  : _hotKeyBackend = hotKeyBackend ??
            SystemDesktopShortcutHotKeyBackend('magicchat.desktop.search'),
        _platform = platform ?? defaultTargetPlatform;

  final DesktopShortcutHotKeyBackend _hotKeyBackend;
  final TargetPlatform _platform;
  DesktopSearchShortcut? _registeredShortcut;
  AsyncCallback? _registeredHandler;

  bool get isSupported => isDesktopShortcutPlatform(_platform);

  Future<bool> beginRecording() async {
    if (!isSupported) return true;
    try {
      await _hotKeyBackend.unregister();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelRecording() async {
    final shortcut = _registeredShortcut;
    final handler = _registeredHandler;
    if (shortcut == null || handler == null) return true;
    return configure(shortcut, handler);
  }

  Future<bool> configure(
      DesktopSearchShortcut shortcut, AsyncCallback onTriggered) async {
    if (!isSupported) return true;
    final previous = _registeredShortcut;
    final previousHandler = _registeredHandler;
    try {
      await _hotKeyBackend.unregister();
      if (shortcut.enabled) {
        await _hotKeyBackend.register(shortcut, onTriggered);
      }
      _registeredShortcut = shortcut;
      _registeredHandler = onTriggered;
      return true;
    } catch (_) {
      if (previous?.enabled == true && previousHandler != null) {
        try {
          await _hotKeyBackend.register(previous!, previousHandler);
        } catch (_) {}
      }
      return false;
    }
  }

  Future<void> dispose() => _hotKeyBackend.unregister();
}
