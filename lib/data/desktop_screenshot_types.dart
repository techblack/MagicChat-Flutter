import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DesktopScreenshotMode { region, screen }

abstract interface class DesktopScreenshotCaptureBackend {
  Future<bool> isAccessAllowed();

  Future<void> requestAccess({required bool openSettingsOnly});

  Future<CapturedScreenshot?> capture(
      DesktopScreenshotMode mode, String imagePath);
}

abstract interface class DesktopScreenshotHotKeyBackend {
  Future<void> register(
      DesktopScreenshotShortcut shortcut, AsyncCallback onTriggered);

  Future<void> unregister();
}

enum DesktopScreenshotErrorCode {
  permissionDenied,
  unavailable,
  busy,
  imageTooLarge,
  failed,
}

class DesktopScreenshotException implements Exception {
  const DesktopScreenshotException(this.code, this.message);

  final DesktopScreenshotErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class CapturedScreenshot {
  const CapturedScreenshot({
    required this.bytes,
    required this.width,
    required this.height,
    required this.fileName,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String fileName;
}

enum DesktopShortcutModifier { control, meta, alt, shift }

class DesktopScreenshotShortcut {
  const DesktopScreenshotShortcut({
    required this.keyCode,
    required this.modifiers,
    this.enabled = true,
  });

  final int keyCode;
  final Set<DesktopShortcutModifier> modifiers;
  final bool enabled;

  factory DesktopScreenshotShortcut.defaultFor(TargetPlatform platform) =>
      DesktopScreenshotShortcut(
        keyCode: PhysicalKeyboardKey.keyA.usbHidUsage,
        modifiers: {
          if (platform == TargetPlatform.macOS)
            DesktopShortcutModifier.meta
          else
            DesktopShortcutModifier.control,
          DesktopShortcutModifier.shift,
        },
      );

  factory DesktopScreenshotShortcut.fromJson(
      Map<String, dynamic> value, TargetPlatform platform) {
    final keyCode = value['key_code'];
    final rawModifiers = value['modifiers'];
    final enabled = value['enabled'];
    if (keyCode is! int || rawModifiers is! List || enabled is! bool) {
      return DesktopScreenshotShortcut.defaultFor(platform);
    }
    final modifiers = rawModifiers
        .whereType<String>()
        .map((name) => DesktopShortcutModifier.values
            .where((modifier) => modifier.name == name)
            .firstOrNull)
        .whereType<DesktopShortcutModifier>()
        .toSet();
    final shortcut = DesktopScreenshotShortcut(
        keyCode: keyCode, modifiers: modifiers, enabled: enabled);
    return shortcut.isValid
        ? shortcut
        : DesktopScreenshotShortcut.defaultFor(platform);
  }

  bool get isValid {
    final key = PhysicalKeyboardKey.findKeyByCode(keyCode);
    final primary = modifiers.contains(DesktopShortcutModifier.control) ||
        modifiers.contains(DesktopShortcutModifier.meta) ||
        modifiers.contains(DesktopShortcutModifier.alt);
    return key != null && !_modifierKeys.contains(key) && primary;
  }

  PhysicalKeyboardKey? get physicalKey =>
      PhysicalKeyboardKey.findKeyByCode(keyCode);

  DesktopScreenshotShortcut copyWith({
    int? keyCode,
    Set<DesktopShortcutModifier>? modifiers,
    bool? enabled,
  }) =>
      DesktopScreenshotShortcut(
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
      other is DesktopScreenshotShortcut &&
      other.keyCode == keyCode &&
      other.enabled == enabled &&
      setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(keyCode, enabled,
      Object.hashAll(modifiers.toList()..sort((a, b) => a.index - b.index)));
}

final _modifierKeys = {
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
};

String _keyLabel(PhysicalKeyboardKey? key) {
  final name = key?.debugName;
  if (name == null || name.isEmpty) return '按键';
  return name.startsWith('Key ') ? name.substring(4) : name;
}

bool isDesktopScreenshotPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.macOS ||
    platform == TargetPlatform.linux;
