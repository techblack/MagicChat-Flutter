import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:magicchat_client/features/settings/account_deactivation_page.dart';
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
    expect(find.text('存储空间'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);

    await expectLater(
      find.byKey(const ValueKey('settings-page-golden')),
      matchesGoldenFile('evidence/settings_page.png'),
    );

    await tester.scrollUntilVisible(find.text('退出登录'), 500,
        scrollable: find.byType(Scrollable).last);
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

    final toggle = find.byType(SwitchListTile);
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('系统通知权限未开启，请在系统设置中允许通知'), findsOneWidget);
    expect((tester.widget<SwitchListTile>(toggle)).value, isFalse);
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

    expect(find.byType(AccountDeactivationPage), findsOneWidget);
    expect(find.text('demo@example.com'), findsOneWidget);
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
