import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DesktopShortcutModifier { control, meta, alt, shift }

enum DesktopShortcutUpdateStatus {
  updated,
  conflict,
  saveFailed,
  restoreFailed,
}

Future<DesktopShortcutUpdateStatus> updateDesktopShortcut<T>(
    {required T previous,
    required T candidate,
    required Future<bool> Function(T shortcut) configure,
    required Future<void> Function(T shortcut) persist}) async {
  if (!await configure(candidate)) return DesktopShortcutUpdateStatus.conflict;
  try {
    await persist(candidate);
    return DesktopShortcutUpdateStatus.updated;
  } catch (_) {
    return await configure(previous)
        ? DesktopShortcutUpdateStatus.saveFailed
        : DesktopShortcutUpdateStatus.restoreFailed;
  }
}

class DesktopGlobalShortcut {
  const DesktopGlobalShortcut({
    required this.keyCode,
    required this.modifiers,
    this.enabled = true,
  });

  final int keyCode;
  final Set<DesktopShortcutModifier> modifiers;
  final bool enabled;

  factory DesktopGlobalShortcut.fromJson(
      Map<String, dynamic> value, DesktopGlobalShortcut fallback) {
    final keyCode = value['key_code'];
    final rawModifiers = value['modifiers'];
    final enabled = value['enabled'];
    if (keyCode is! int || rawModifiers is! List || enabled is! bool) {
      return fallback;
    }
    final modifiers = rawModifiers
        .whereType<String>()
        .map((name) => DesktopShortcutModifier.values
            .where((modifier) => modifier.name == name)
            .firstOrNull)
        .whereType<DesktopShortcutModifier>()
        .toSet();
    final shortcut = DesktopGlobalShortcut(
        keyCode: keyCode, modifiers: modifiers, enabled: enabled);
    return shortcut.isValid ? shortcut : fallback;
  }

  bool get isValid {
    final key = PhysicalKeyboardKey.findKeyByCode(keyCode);
    final primary = modifiers.contains(DesktopShortcutModifier.control) ||
        modifiers.contains(DesktopShortcutModifier.meta) ||
        modifiers.contains(DesktopShortcutModifier.alt);
    return key != null && !desktopShortcutModifierKeys.contains(key) && primary;
  }

  PhysicalKeyboardKey? get physicalKey =>
      PhysicalKeyboardKey.findKeyByCode(keyCode);

  DesktopGlobalShortcut copyWith({
    int? keyCode,
    Set<DesktopShortcutModifier>? modifiers,
    bool? enabled,
  }) =>
      DesktopGlobalShortcut(
        keyCode: keyCode ?? this.keyCode,
        modifiers: modifiers ?? this.modifiers,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'key_code': keyCode,
        'modifiers': modifiers.map((modifier) => modifier.name).toList()
          ..sort(),
        'enabled': enabled,
      };

  String label(TargetPlatform platform) {
    final labels = <String>[
      if (modifiers.contains(DesktopShortcutModifier.control))
        platform == TargetPlatform.macOS ? '⌃' : 'Ctrl',
      if (modifiers.contains(DesktopShortcutModifier.meta))
        platform == TargetPlatform.macOS ? '⌘' : 'Win',
      if (modifiers.contains(DesktopShortcutModifier.alt))
        platform == TargetPlatform.macOS ? '⌥' : 'Alt',
      if (modifiers.contains(DesktopShortcutModifier.shift))
        platform == TargetPlatform.macOS ? '⇧' : 'Shift',
      _keyLabel(physicalKey),
    ];
    return labels.join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopGlobalShortcut &&
      other.keyCode == keyCode &&
      other.enabled == enabled &&
      setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(keyCode, enabled,
      Object.hashAll(modifiers.toList()..sort((a, b) => a.index - b.index)));
}

abstract interface class DesktopShortcutHotKeyBackend {
  Future<void> register(
      DesktopGlobalShortcut shortcut, AsyncCallback onTriggered);

  Future<void> unregister();
}

final desktopShortcutModifierKeys = {
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
};

bool isDesktopShortcutPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.macOS ||
    platform == TargetPlatform.linux;

String _keyLabel(PhysicalKeyboardKey? key) {
  final name = key?.debugName;
  if (name == null || name.isEmpty) return '按键';
  return name.startsWith('Key ') ? name.substring(4) : name;
}
