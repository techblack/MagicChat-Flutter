import 'package:flutter/services.dart';

import 'desktop_shortcut.dart';

export 'desktop_shortcut.dart';

class DesktopSearchShortcut extends DesktopGlobalShortcut {
  const DesktopSearchShortcut({
    required super.keyCode,
    required super.modifiers,
    super.enabled = true,
  });

  factory DesktopSearchShortcut.defaultFor(TargetPlatform platform) =>
      DesktopSearchShortcut(
        keyCode: PhysicalKeyboardKey.keyF.usbHidUsage,
        modifiers: {
          if (platform == TargetPlatform.macOS)
            DesktopShortcutModifier.meta
          else
            DesktopShortcutModifier.control,
          DesktopShortcutModifier.shift,
        },
      );

  factory DesktopSearchShortcut.fromJson(
      Map<String, dynamic> value, TargetPlatform platform) {
    final parsed = DesktopGlobalShortcut.fromJson(
        value, DesktopSearchShortcut.defaultFor(platform));
    return DesktopSearchShortcut(
        keyCode: parsed.keyCode,
        modifiers: parsed.modifiers,
        enabled: parsed.enabled);
  }

  @override
  DesktopSearchShortcut copyWith({
    int? keyCode,
    Set<DesktopShortcutModifier>? modifiers,
    bool? enabled,
  }) =>
      DesktopSearchShortcut(
        keyCode: keyCode ?? this.keyCode,
        modifiers: modifiers ?? this.modifiers,
        enabled: enabled ?? this.enabled,
      );
}
