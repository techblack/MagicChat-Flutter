import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

import 'desktop_screenshot_types.dart';
import 'desktop_shortcut_io.dart';

class SystemDesktopScreenshotCaptureBackend
    implements DesktopScreenshotCaptureBackend {
  const SystemDesktopScreenshotCaptureBackend();

  @override
  Future<bool> isAccessAllowed() => screenCapturer.isAccessAllowed();

  @override
  Future<void> requestAccess({required bool openSettingsOnly}) =>
      screenCapturer.requestAccess(onlyOpenPrefPane: openSettingsOnly);

  @override
  Future<CapturedScreenshot?> capture(
      DesktopScreenshotMode mode, String imagePath) async {
    final result = await screenCapturer.capture(
      mode: mode == DesktopScreenshotMode.region
          ? CaptureMode.region
          : CaptureMode.screen,
      imagePath: imagePath,
      copyToClipboard: false,
    );
    final bytes = result?.imageBytes;
    if (result == null || bytes == null || bytes.isEmpty) return null;
    return CapturedScreenshot(
      bytes: bytes,
      width: result.imageWidth ?? 0,
      height: result.imageHeight ?? 0,
      fileName: p.basename(imagePath),
    );
  }
}

class SystemDesktopScreenshotHotKeyBackend
    implements DesktopScreenshotHotKeyBackend {
  final _backend =
      SystemDesktopShortcutHotKeyBackend('magicchat.desktop.screenshot');

  @override
  Future<void> register(
      DesktopScreenshotShortcut shortcut, AsyncCallback onTriggered) async {
    if (!shortcut.isValid) {
      throw const DesktopScreenshotException(
          DesktopScreenshotErrorCode.failed, '截图快捷键无效');
    }
    await _backend.register(shortcut, onTriggered);
  }

  @override
  Future<void> unregister() => _backend.unregister();
}

class DesktopScreenshotController {
  DesktopScreenshotController({
    DesktopScreenshotCaptureBackend? captureBackend,
    DesktopScreenshotHotKeyBackend? hotKeyBackend,
    TargetPlatform? platform,
    Future<String> Function()? temporaryDirectoryPath,
  })  : _captureBackend =
            captureBackend ?? const SystemDesktopScreenshotCaptureBackend(),
        _hotKeyBackend =
            hotKeyBackend ?? SystemDesktopScreenshotHotKeyBackend(),
        _platform = platform ?? defaultTargetPlatform,
        _temporaryDirectoryPath = temporaryDirectoryPath ??
            (() async => (await getTemporaryDirectory()).path);

  static const maxImageBytes = desktopScreenshotMaxImageBytes;

  final DesktopScreenshotCaptureBackend _captureBackend;
  final DesktopScreenshotHotKeyBackend _hotKeyBackend;
  final TargetPlatform _platform;
  final Future<String> Function() _temporaryDirectoryPath;
  DesktopScreenshotShortcut? _registeredShortcut;
  AsyncCallback? _registeredHandler;
  bool _capturing = false;

  bool get isSupported => isDesktopScreenshotPlatform(_platform);

  Future<bool> configure(
      DesktopScreenshotShortcut shortcut, AsyncCallback onTriggered) async {
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

  Future<CapturedScreenshot?> capture(DesktopScreenshotMode mode) async {
    if (!isSupported) {
      throw const DesktopScreenshotException(
          DesktopScreenshotErrorCode.unavailable, '当前平台不支持桌面截图');
    }
    if (_capturing) {
      throw const DesktopScreenshotException(
          DesktopScreenshotErrorCode.busy, '已有截图正在进行');
    }
    _capturing = true;
    File? temporaryFile;
    try {
      if (_platform == TargetPlatform.macOS &&
          !await _captureBackend.isAccessAllowed()) {
        await _captureBackend.requestAccess(openSettingsOnly: false);
        if (!await _captureBackend.isAccessAllowed()) {
          throw const DesktopScreenshotException(
            DesktopScreenshotErrorCode.permissionDenied,
            '需要在系统设置中允许 MagicChat 录制屏幕后才能截图',
          );
        }
      }
      final directory = Directory(
          p.join(await _temporaryDirectoryPath(), 'magicchat-screenshots'));
      directory.createSync(recursive: true);
      final fileName = 'MagicChat-${DateTime.now().millisecondsSinceEpoch}.png';
      temporaryFile = File(p.join(directory.path, fileName));
      final captured = await _captureBackend.capture(mode, temporaryFile.path);
      if (captured == null) return null;
      if (captured.bytes.length > maxImageBytes) {
        throw const DesktopScreenshotException(
          DesktopScreenshotErrorCode.imageTooLarge,
          '截图超过 32MiB，请缩小选择区域后重试',
        );
      }
      return CapturedScreenshot(
        bytes: captured.bytes,
        width: captured.width,
        height: captured.height,
        fileName: fileName,
      );
    } on DesktopScreenshotException {
      rethrow;
    } on ProcessException {
      throw DesktopScreenshotException(
        DesktopScreenshotErrorCode.unavailable,
        _platform == TargetPlatform.linux
            ? '系统截图工具不可用，请安装 gnome-screenshot 或 KDE Spectacle'
            : '系统截图工具不可用',
      );
    } catch (_) {
      throw const DesktopScreenshotException(
          DesktopScreenshotErrorCode.failed, '截图失败，请稍后重试');
    } finally {
      _capturing = false;
      if (temporaryFile != null && temporaryFile.existsSync()) {
        temporaryFile.deleteSync();
      }
    }
  }

  Future<void> openPermissionSettings() =>
      _captureBackend.requestAccess(openSettingsOnly: true);

  Future<void> dispose() => _hotKeyBackend.unregister();
}
