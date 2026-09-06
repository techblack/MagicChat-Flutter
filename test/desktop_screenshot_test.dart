import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/desktop_screenshot.dart';
import 'package:magicchat_client/data/desktop_screenshot_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('截图快捷键按平台提供默认值并持久化禁用状态', () async {
    final windows =
        DesktopScreenshotShortcut.defaultFor(TargetPlatform.windows);
    final macOS = DesktopScreenshotShortcut.defaultFor(TargetPlatform.macOS);
    expect(windows.label(TargetPlatform.windows), 'Ctrl+Shift+A');
    expect(macOS.label(TargetPlatform.macOS), '⌘+⇧+A');

    const preferences = DesktopScreenshotPreferences();
    await preferences.write(windows.copyWith(enabled: false));
    final restored = await preferences.read(TargetPlatform.windows);
    expect(restored.enabled, isFalse);
    expect(restored.keyCode, PhysicalKeyboardKey.keyA.usbHidUsage);
  });

  test('系统截图入口仅在三个桌面平台开放', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      expect(isDesktopScreenshotPlatform(platform), isTrue);
    }
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      expect(isDesktopScreenshotPlatform(platform), isFalse);
    }
    expect(DesktopScreenshotController.maxImageBytes,
        desktopScreenshotMaxImageBytes);
  });

  test('损坏的快捷键配置回退到平台默认值', () async {
    SharedPreferences.setMockInitialValues({
      DesktopScreenshotPreferences.shortcutKey: '{invalid',
    });
    final value =
        await const DesktopScreenshotPreferences().read(TargetPlatform.linux);
    expect(value, DesktopScreenshotShortcut.defaultFor(TargetPlatform.linux));
  });

  test('区域和全屏截图返回真实字节并清理临时结果文件', () async {
    final temporary = await Directory.systemTemp.createTemp('magicchat-shot-');
    addTearDown(() => temporary.delete(recursive: true));
    final backend = _CaptureBackend();
    final controller = DesktopScreenshotController(
      captureBackend: backend,
      hotKeyBackend: _HotKeyBackend(),
      platform: TargetPlatform.linux,
      temporaryDirectoryPath: () async => temporary.path,
    );

    for (final mode in DesktopScreenshotMode.values) {
      final result = await controller.capture(mode);

      expect(result?.bytes, _pngBytes);
      expect(result?.width, 1);
      expect(backend.mode, mode);
      expect(backend.path, endsWith('.png'));
      expect(File(backend.path!).existsSync(), isFalse);
    }
  });

  test('macOS 权限拒绝返回稳定错误并可打开权限设置', () async {
    final temporary = await Directory.systemTemp.createTemp('magicchat-shot-');
    addTearDown(() => temporary.delete(recursive: true));
    final backend = _CaptureBackend(accessAllowed: false);
    final controller = DesktopScreenshotController(
      captureBackend: backend,
      hotKeyBackend: _HotKeyBackend(),
      platform: TargetPlatform.macOS,
      temporaryDirectoryPath: () async => temporary.path,
    );

    await expectLater(
      controller.capture(DesktopScreenshotMode.region),
      throwsA(isA<DesktopScreenshotException>().having((error) => error.code,
          'code', DesktopScreenshotErrorCode.permissionDenied)),
    );
    expect(backend.permissionRequests, 1);
    await controller.openPermissionSettings();
    expect(backend.settingsRequests, 1);
  });

  test('快捷键注册冲突时恢复上一组有效快捷键', () async {
    final hotKeys = _HotKeyBackend();
    final controller = DesktopScreenshotController(
      captureBackend: _CaptureBackend(),
      hotKeyBackend: hotKeys,
      platform: TargetPlatform.windows,
    );
    final initial =
        DesktopScreenshotShortcut.defaultFor(TargetPlatform.windows);
    expect(await controller.configure(initial, () async {}), isTrue);
    hotKeys.failNextRegistration = true;
    final replacement =
        initial.copyWith(keyCode: PhysicalKeyboardKey.keyS.usbHidUsage);

    expect(await controller.configure(replacement, () async {}), isFalse);
    expect(hotKeys.registered, initial);
  });

  test('已注册的系统快捷键触发截图请求回调', () async {
    final hotKeys = _HotKeyBackend();
    final controller = DesktopScreenshotController(
      captureBackend: _CaptureBackend(),
      hotKeyBackend: hotKeys,
      platform: TargetPlatform.windows,
    );
    var triggerCount = 0;
    await controller.configure(
      DesktopScreenshotShortcut.defaultFor(TargetPlatform.windows),
      () async => triggerCount++,
    );

    await hotKeys.trigger();

    expect(triggerCount, 1);
  });
}

class _CaptureBackend implements DesktopScreenshotCaptureBackend {
  _CaptureBackend({this.accessAllowed = true});

  bool accessAllowed;
  int permissionRequests = 0;
  int settingsRequests = 0;
  DesktopScreenshotMode? mode;
  String? path;

  @override
  Future<CapturedScreenshot?> capture(
      DesktopScreenshotMode mode, String imagePath) async {
    this.mode = mode;
    path = imagePath;
    await File(imagePath).writeAsBytes(_pngBytes);
    return CapturedScreenshot(
        bytes: _pngBytes,
        width: 1,
        height: 1,
        fileName: imagePath.split(Platform.pathSeparator).last);
  }

  @override
  Future<bool> isAccessAllowed() async => accessAllowed;

  @override
  Future<void> requestAccess({required bool openSettingsOnly}) async {
    if (openSettingsOnly) {
      settingsRequests++;
    } else {
      permissionRequests++;
    }
  }
}

class _HotKeyBackend implements DesktopScreenshotHotKeyBackend {
  DesktopScreenshotShortcut? registered;
  AsyncCallback? handler;
  bool failNextRegistration = false;

  @override
  Future<void> register(
      DesktopScreenshotShortcut shortcut, AsyncCallback onTriggered) async {
    if (failNextRegistration) {
      failNextRegistration = false;
      throw StateError('conflict');
    }
    registered = shortcut;
    handler = onTriggered;
  }

  @override
  Future<void> unregister() async {
    registered = null;
    handler = null;
  }

  Future<void> trigger() async => handler?.call();
}

final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
