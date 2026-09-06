import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_shortcut.dart';

export 'desktop_shortcut.dart';

enum DesktopScreenshotMode { region, screen }

const desktopScreenshotMaxImageBytes = 32 * 1024 * 1024;

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

class DesktopScreenshotShortcut extends DesktopGlobalShortcut {
  const DesktopScreenshotShortcut({
    required super.keyCode,
    required super.modifiers,
    super.enabled = true,
  });

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
    final parsed = DesktopGlobalShortcut.fromJson(
        value, DesktopScreenshotShortcut.defaultFor(platform));
    return DesktopScreenshotShortcut(
        keyCode: parsed.keyCode,
        modifiers: parsed.modifiers,
        enabled: parsed.enabled);
  }

  @override
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
}

bool isDesktopScreenshotPlatform(TargetPlatform platform) =>
    isDesktopShortcutPlatform(platform);
