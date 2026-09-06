import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/desktop_auto_launch.dart';
import 'package:magicchat_client/data/desktop_system_tray.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('隐藏启动在登录页也先创建系统托盘', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tray = _FakeTray(ready: true);
    final window = _FakeWindow();

    await tester.pumpWidget(
      MagicChatApp(
        launchArguments: const ['--hidden'],
        desktopAutoLaunch: _FakeAutoLaunch(enabled: true),
        desktopTray: tray,
        desktopWindowController: window,
      ),
    );
    await tester.pump();

    expect(tray.initializeCount, 1);
    expect(window.showCount, 0);
  });

  testWidgets('隐藏启动但托盘不可用时自动显示窗口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tray = _FakeTray(ready: false);
    final window = _FakeWindow();

    await tester.pumpWidget(
      MagicChatApp(
        launchArguments: const ['--hidden'],
        desktopAutoLaunch: _FakeAutoLaunch(enabled: true),
        desktopTray: tray,
        desktopWindowController: window,
      ),
    );
    await tester.pump();

    expect(tray.initializeCount, 1);
    expect(window.showCount, 1);
  });

  testWidgets('手动 hidden 参数在启动项关闭时不会隐身', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final window = _FakeWindow();

    await tester.pumpWidget(
      MagicChatApp(
        launchArguments: const ['--hidden'],
        desktopAutoLaunch: _FakeAutoLaunch(enabled: false),
        desktopTray: _FakeTray(ready: true),
        desktopWindowController: window,
      ),
    );
    await tester.pump();

    expect(window.showCount, 1);
  });
}

class _FakeAutoLaunch implements DesktopAutoLaunchController {
  _FakeAutoLaunch({required this.enabled});

  final bool enabled;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool enabled) async {}
}

class _FakeTray implements DesktopSystemTrayController {
  _FakeTray({required this.ready});

  final bool ready;
  int initializeCount = 0;

  @override
  Future<bool> initialize({
    required void Function(String conversationId) onOpenConversation,
  }) async {
    initializeCount++;
    return ready;
  }

  @override
  Future<void> update({
    required int unreadCount,
    required Iterable<ChatConversation> conversations,
    required MessageNotificationPrivacy privacy,
    Iterable<Contact> contacts = const [],
  }) async {}

  @override
  Future<void> handleMenuAction(String? key) async {}

  @override
  Future<void> dispose() async {}
}

class _FakeWindow implements DesktopWindowController {
  int showCount = 0;

  @override
  Future<void> show() async => showCount++;

  @override
  Future<void> quit() async {}

  @override
  Future<void> setTrayReady(bool ready) async {}

  @override
  Future<void> setCloseBehavior(DesktopCloseBehavior behavior) async {}
}
