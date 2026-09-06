import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/desktop_search_shortcut.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('系统搜索快捷键先恢复窗口再打开综合搜索', (tester) async {
    const channel = MethodChannel('magicchat/desktop_window');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final backend = _HotKeyBackend();
    final controller = DesktopSearchShortcutController(
        hotKeyBackend: backend, platform: TargetPlatform.linux);

    await tester.pumpWidget(MaterialApp(
        home: AppShell(
            repository: DemoRepository(), desktopSearchShortcut: controller)));
    await tester.pumpAndSettle();
    expect(backend.registered,
        DesktopSearchShortcut.defaultFor(TargetPlatform.linux));

    backend.trigger();
    await tester.pumpAndSettle();

    expect(calls, contains('show'));
    expect(find.text('综合搜索'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('设置页支持禁用、录制并恢复默认搜索快捷键', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final changes = <DesktopSearchShortcut>[];
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                searchShortcut:
                    DesktopSearchShortcut.defaultFor(TargetPlatform.linux),
                onSearchShortcutChanged: (shortcut) async {
                  changes.add(shortcut);
                  return DesktopShortcutUpdateStatus.updated;
                }))));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '全局搜索快捷键');
    await tester.ensureVisible(toggle);
    expect(find.text('Ctrl+Shift+F · 全局打开综合搜索'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(changes.last.enabled, isFalse);
    expect(find.text('已禁用'), findsWidgets);

    await tester.tap(find.text('修改全局搜索快捷键'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS,
        physicalKey: PhysicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Ctrl+Shift+S'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(changes.last.label(TargetPlatform.linux), 'Ctrl+Shift+S');

    await tester.tap(find.text('修改全局搜索快捷键'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
        changes.last, DesktopSearchShortcut.defaultFor(TargetPlatform.linux));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('搜索快捷键冲突时提示并保留旧组合', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                searchShortcut:
                    DesktopSearchShortcut.defaultFor(TargetPlatform.linux),
                onSearchShortcutChanged: (_) async =>
                    DesktopShortcutUpdateStatus.conflict))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('修改全局搜索快捷键'));
    await tester.tap(find.text('修改全局搜索快捷键'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS,
        physicalKey: PhysicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('该快捷键已被系统或其他应用占用'), findsOneWidget);
    expect(find.text('Ctrl+Shift+F · 全局打开综合搜索'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('搜索快捷键更新期间重复触发只执行一次', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<DesktopShortcutUpdateStatus>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                searchShortcut:
                    DesktopSearchShortcut.defaultFor(TargetPlatform.linux),
                onSearchShortcutChanged: (_) {
                  calls++;
                  return pending.future;
                }))));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '全局搜索快捷键');
    await tester.ensureVisible(toggle);
    final trigger = tester.widget<SwitchListTile>(toggle).onChanged!;
    trigger(false);
    trigger(false);
    await tester.pump();

    expect(calls, 1);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, '修改全局搜索快捷键'))
            .onTap,
        isNull);
    pending.complete(DesktopShortcutUpdateStatus.updated);
    await tester.pumpAndSettle();
    expect(find.text('已禁用'), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _HotKeyBackend implements DesktopShortcutHotKeyBackend {
  DesktopGlobalShortcut? registered;
  AsyncCallback? handler;

  @override
  Future<void> register(
      DesktopGlobalShortcut shortcut, AsyncCallback onTriggered) async {
    registered = shortcut;
    handler = onTriggered;
  }

  @override
  Future<void> unregister() async {
    registered = null;
    handler = null;
  }

  void trigger() => handler?.call();
}
