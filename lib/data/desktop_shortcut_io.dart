import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'desktop_shortcut.dart';

class SystemDesktopShortcutHotKeyBackend
    implements DesktopShortcutHotKeyBackend {
  SystemDesktopShortcutHotKeyBackend(this.identifier);

  final String identifier;
  HotKey? _registered;

  @override
  Future<void> register(
      DesktopGlobalShortcut shortcut, AsyncCallback onTriggered) async {
    final key = shortcut.physicalKey;
    if (key == null || !shortcut.isValid) {
      throw StateError('系统快捷键无效');
    }
    final hotKey = HotKey(
      identifier: identifier,
      key: key,
      modifiers: shortcut.modifiers.map(_modifier).toList(growable: false),
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => unawaited(onTriggered()),
    );
    _registered = hotKey;
  }

  @override
  Future<void> unregister() async {
    final hotKey = _registered;
    _registered = null;
    if (hotKey != null) await hotKeyManager.unregister(hotKey);
  }

  HotKeyModifier _modifier(DesktopShortcutModifier modifier) =>
      switch (modifier) {
        DesktopShortcutModifier.control => HotKeyModifier.control,
        DesktopShortcutModifier.meta => HotKeyModifier.meta,
        DesktopShortcutModifier.alt => HotKeyModifier.alt,
        DesktopShortcutModifier.shift => HotKeyModifier.shift,
      };
}
