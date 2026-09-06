import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/desktop_search_shortcut.dart';
import 'package:magicchat_client/data/desktop_search_shortcut_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('全局搜索快捷键按平台提供默认值并持久化禁用状态', () async {
    final windows = DesktopSearchShortcut.defaultFor(TargetPlatform.windows);
    final macOS = DesktopSearchShortcut.defaultFor(TargetPlatform.macOS);
    expect(windows.label(TargetPlatform.windows), 'Ctrl+Shift+F');
    expect(macOS.label(TargetPlatform.macOS), '⌘+⇧+F');

    const preferences = DesktopSearchShortcutPreferences();
    await preferences.write(windows.copyWith(enabled: false));
    final restored = await preferences.read(TargetPlatform.windows);
    expect(restored.enabled, isFalse);
    expect(restored.keyCode, PhysicalKeyboardKey.keyF.usbHidUsage);
  });

  test('损坏的搜索快捷键配置回退到平台默认值', () async {
    SharedPreferences.setMockInitialValues({
      DesktopSearchShortcutPreferences.shortcutKey: '{invalid',
    });
    expect(
        await const DesktopSearchShortcutPreferences()
            .read(TargetPlatform.linux),
        DesktopSearchShortcut.defaultFor(TargetPlatform.linux));
  });

  test('搜索快捷键注册冲突时恢复旧组合并保持触发回调', () async {
    final backend = _HotKeyBackend();
    final controller = DesktopSearchShortcutController(
        hotKeyBackend: backend, platform: TargetPlatform.windows);
    final initial = DesktopSearchShortcut.defaultFor(TargetPlatform.windows);
    var triggers = 0;
    expect(await controller.configure(initial, () async => triggers++), isTrue);
    backend.failNextRegistration = true;

    expect(
        await controller.configure(
            initial.copyWith(keyCode: PhysicalKeyboardKey.keyS.usbHidUsage),
            () async {}),
        isFalse);
    expect(backend.registered, initial);
    await backend.trigger();
    expect(triggers, 1);
    await controller.dispose();
  });

  test('录制期间暂停搜索快捷键并在取消时恢复', () async {
    final backend = _HotKeyBackend();
    final controller = DesktopSearchShortcutController(
        hotKeyBackend: backend, platform: TargetPlatform.windows);
    final initial = DesktopSearchShortcut.defaultFor(TargetPlatform.windows);
    await controller.configure(initial, () async {});

    expect(await controller.beginRecording(), isTrue);
    expect(backend.registered, isNull);
    expect(await controller.cancelRecording(), isTrue);
    expect(backend.registered, initial);
    expect(
        await controller.configure(
            initial.copyWith(enabled: false), () async {}),
        isTrue);
    expect(backend.registered, isNull);
    await controller.dispose();
  });

  test('搜索快捷键保存失败时恢复旧注册组合', () async {
    final previous = DesktopSearchShortcut.defaultFor(TargetPlatform.windows);
    final candidate =
        previous.copyWith(keyCode: PhysicalKeyboardKey.keyS.usbHidUsage);
    final configured = <DesktopSearchShortcut>[];

    final status = await updateDesktopShortcut(
      previous: previous,
      candidate: candidate,
      configure: (shortcut) async {
        configured.add(shortcut);
        return true;
      },
      persist: (_) => throw StateError('save failed'),
    );

    expect(status, DesktopShortcutUpdateStatus.saveFailed);
    expect(configured, [candidate, previous]);
  });
}

class _HotKeyBackend implements DesktopShortcutHotKeyBackend {
  DesktopGlobalShortcut? registered;
  AsyncCallback? handler;
  bool failNextRegistration = false;

  @override
  Future<void> register(
      DesktopGlobalShortcut shortcut, AsyncCallback onTriggered) async {
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
