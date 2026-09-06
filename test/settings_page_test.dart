import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/desktop_auto_launch.dart';
import 'package:magicchat_client/data/desktop_window_controller.dart';
import 'package:magicchat_client/data/update_service.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:magicchat_client/features/settings/account_deactivation_page.dart';
import 'package:magicchat_client/features/settings/server_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('设置页展示账户、服务器、通知与存储入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1042, 662));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('settings-page-golden'),
        child: SizedBox(
          width: 1042,
          height: 662,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
                useMaterial3: true),
            home: Scaffold(
              appBar: AppBar(title: const Text('设置')),
              body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onLogout: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('演示用户'), findsOneWidget);
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);

    await expectLater(
      find.byKey(const ValueKey('settings-page-golden')),
      matchesGoldenFile('evidence/settings_page.png'),
    );

    final scrollable = find.byType(Scrollable).last;
    for (var i = 0; i < 8 && find.text('存储空间').evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -480));
      await tester.pump();
    }
    expect(find.text('存储空间'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    for (var i = 0; i < 8 && find.text('退出登录').evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -480));
      await tester.pump();
    }
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('更新行显示当前版本并在检查期间阻止重复触发', (tester) async {
    final pending = Completer<AppRelease?>();
    final service = _FakeUpdateService([() => pending.future]);
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                updateService: service))));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('检查更新'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('当前版本 ${UpdateService.currentVersion}'), findsOneWidget);

    await tester.tap(find.text('检查更新'));
    await tester.pump();
    expect(find.text('正在检查更新'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '检查更新')).onTap,
        isNull);
    expect(service.checks, 1);

    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
        find.text('当前已是最新版本（${UpdateService.currentVersion}）'), findsOneWidget);
    expect(service.checks, 1);
  });

  testWidgets('检查更新失败后在设置行原位重试', (tester) async {
    final service = _FakeUpdateService([
      () async => throw const FormatException('版本服务暂时不可用'),
      () async => null,
    ]);
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                updateService: service))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('检查更新'), 250,
        scrollable: find.byType(Scrollable).first);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('检查失败：版本服务暂时不可用，点击重试'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(service.checks, 1);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(
        find.text('当前已是最新版本（${UpdateService.currentVersion}）'), findsOneWidget);
    expect(service.checks, 2);
  });

  testWidgets('系统拒绝通知权限时开关回滚并提示用户', (tester) async {
    const channel = MethodChannel('magicchat/notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermission') return false;
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com'))));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '通知');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('系统通知权限未开启，请在系统设置中允许通知'), findsOneWidget);
    expect((tester.widget<SwitchListTile>(toggle)).value, isFalse);
  });

  testWidgets('新消息提示音开关即时回调', (tester) async {
    bool? enabled = true;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onMessageSoundChanged: (value) => enabled = value))));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '新消息提示音');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
  });

  testWidgets('通知隐私选择即时回调', (tester) async {
    MessageNotificationPrivacy? privacy = MessageNotificationPrivacy.preview;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onNotificationPrivacyChanged: (value) => privacy = value))));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButton<MessageNotificationPrivacy>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅显示来源').last);
    await tester.pumpAndSettle();
    expect(privacy, MessageNotificationPrivacy.metadata);
  });

  testWidgets('界面字体大小选择即时回调', (tester) async {
    InterfaceFontScale? selected;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onInterfaceFontScaleChanged: (value) => selected = value))));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButton<InterfaceFontScale>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('中等 120%').last);
    await tester.pumpAndSettle();

    expect(selected, InterfaceFontScale.medium);
  });

  testWidgets('桌面关闭窗口行为可以切换为退出应用', (tester) async {
    DesktopCloseBehavior? selected;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                desktopAutoLaunch: _FakeDesktopAutoLaunch(isSupported: false),
                onDesktopCloseBehaviorChanged: (value) => selected = value))));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButton<DesktopCloseBehavior>);
    expect(dropdown, findsOneWidget);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出应用').last);
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;
    expect(selected, DesktopCloseBehavior.quit);
  });

  testWidgets('退出登录需要二次确认', (tester) async {
    var loggedOut = false;
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onLogout: () async => loggedOut = true))));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 8 && find.text('退出登录').evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -480));
      await tester.pump();
    }
    expect(find.text('退出登录'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('确认退出登录？'), findsOneWidget);
    expect(loggedOut, isFalse);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(loggedOut, isFalse);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
  });

  testWidgets('发送快捷键切换后即时回调并持久化', (tester) async {
    MessageSendShortcut? changed;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onSendMessageShortcutChanged: (value) => changed = value))));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<MessageSendShortcut>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ctrl/⌘+Enter').last);
    await tester.pumpAndSettle();

    expect(changed, MessageSendShortcut.commandOrControlEnter);
    expect(find.text('Ctrl/⌘+Enter 发送，Enter 换行'), findsOneWidget);
    expect(await const ChatPreferences().readSendShortcut(),
        MessageSendShortcut.commandOrControlEnter);
  });

  testWidgets('桌面设置页可启用开机静默自启动', (tester) async {
    final autoLaunch = _FakeDesktopAutoLaunch();
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                desktopAutoLaunch: autoLaunch))));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '开机自动启动');
    expect(toggle, findsOneWidget);
    expect(find.text('登录系统后在后台静默启动'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(autoLaunch.changes, [true]);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('开机自启动设置失败时回滚并提示', (tester) async {
    final autoLaunch = _FakeDesktopAutoLaunch(failChanges: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                desktopAutoLaunch: autoLaunch))));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '开机自动启动');
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('开机自动启动设置失败'), findsOneWidget);
  });

  testWidgets('移动和 Web 能力缺失时不展示开机自启动', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                desktopAutoLaunch:
                    _FakeDesktopAutoLaunch(isSupported: false)))));
    await tester.pumpAndSettle();

    expect(find.text('开机自动启动'), findsNothing);
  });

  testWidgets('账户信息加载失败可重试', (tester) async {
    final repository = _RetryProfileRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: repository,
                serverUrl: 'https://chat.example.com'))));
    await tester.pumpAndSettle();

    expect(find.text('账户信息加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('恢复后的用户'), findsOneWidget);
    expect(repository.attempts, 2);
  });

  testWidgets('设置页可进入当前账号注销流程', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onDeactivateAccount: (_) async {}))));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('注销账号'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('注销账号'));
    await tester.pumpAndSettle();

    expect(find.text('确认注销账号？'), findsOneWidget);
    await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == '输入“注销”继续'),
        '注销');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续注销'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDeactivationPage), findsOneWidget);
    expect(find.text('demo@example.com'), findsOneWidget);
  });

  testWidgets('设置页可进入完整服务器管理页', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com'))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerManagementPage), findsOneWidget);
    expect(find.text('即应官方服务器'), findsOneWidget);
    expect(find.text('chat.example.com'), findsOneWidget);
  });

  testWidgets('设置页只在当前用户资料变更时刷新账户资料', (tester) async {
    final repository = _CountingProfileRepository();
    final store = RealtimeStore()..setCurrentUserId('user-me');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsPage(
                repository: repository,
                serverUrl: 'https://chat.example.com',
                realtimeStore: store))));
    await tester.pumpAndSettle();
    expect(repository.requests, 1);

    store.apply({
      'event': 'user.profile.updated',
      'cursor': 1,
      'payload': {'user_id': 'user-other', 'updated_at': '2026-09-07T12:00:00Z'}
    });
    await tester.pump();
    expect(repository.requests, 1);

    store.apply({
      'event': 'user.profile.updated',
      'cursor': 2,
      'payload': {'user_id': 'user-me', 'updated_at': '2026-09-07T12:01:00Z'}
    });
    await tester.pumpAndSettle();
    expect(repository.requests, 2);
  });
}

class _CountingProfileRepository extends DemoRepository {
  int requests = 0;

  @override
  Future<CurrentUser> currentUser() async {
    requests++;
    return const CurrentUser(
        id: 'user-me', name: '当前用户', email: 'me@example.com');
  }
}

class _RetryProfileRepository extends DemoRepository {
  var attempts = 0;

  @override
  Future<CurrentUser> currentUser() async {
    attempts++;
    if (attempts == 1) throw StateError('offline');
    return const CurrentUser(
        id: 'user-1', name: '恢复后的用户', email: 'user@example.com');
  }
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.actions);

  final List<Future<AppRelease?> Function()> actions;
  int checks = 0;

  @override
  Future<AppRelease?> check() => actions[checks++]();
}

class _FakeDesktopAutoLaunch implements DesktopAutoLaunchController {
  _FakeDesktopAutoLaunch({this.isSupported = true, this.failChanges = false});

  @override
  final bool isSupported;
  final bool failChanges;
  final changes = <bool>[];
  bool enabled = false;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    changes.add(enabled);
    if (failChanges) throw StateError('denied');
    this.enabled = enabled;
  }
}
