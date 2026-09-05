import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
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
