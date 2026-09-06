import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/desktop_system_tray.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('桌面托盘创建未读菜单并处理打开、会话和退出动作', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(const MethodChannel('desktop_tray'),
        (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('desktop_tray'), null));
    final window = _FakeDesktopWindowController();
    String? openedConversation;
    final tray = DesktopSystemTray(
        windowController: window, platform: TargetPlatform.windows);

    expect(
        await tray.initialize(
            onOpenConversation: (value) => openedConversation = value),
        isTrue);
    await tray.update(
      unreadCount: 4,
      conversations: const [
        ChatConversation(
            id: 'conversation-1', title: '设计群', preview: '方案已更新', unread: 4),
      ],
      privacy: MessageNotificationPrivacy.preview,
    );

    final menuCall = calls.lastWhere((call) => call.method == 'setContextMenu');
    final menu = (menuCall.arguments as Map)['menu'] as Map;
    final items = menu['items'] as List;
    expect(
        items.map((item) => (item as Map)['label']),
        containsAll([
          '未读消息',
          '设计群  [4] — 方案已更新',
          '打开 MagicChat',
          '退出 MagicChat',
        ]));
    expect(window.trayReady, isTrue);

    await tray.handleMenuAction('conversation:conversation-1');
    expect(openedConversation, 'conversation-1');
    expect(window.showCount, 1);
    await tray.handleMenuAction('show');
    expect(window.showCount, 2);
    await tray.handleMenuAction('quit');
    expect(window.quitCount, 1);

    await tray.dispose();
    expect(window.trayReady, isFalse);
    expect(calls.any((call) => call.method == 'destroy'), isTrue);
  });

  test('桌面窗口桥接标题、show、托盘就绪和退出方法', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        const MethodChannel('magicchat/desktop_window'), (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('magicchat/desktop_window'), null));

    const controller = PlatformDesktopWindowController();
    await controller.setTitle('(3) 工程群 - MagicChat');
    await controller.setTrayReady(true);
    await controller.setCloseBehavior(DesktopCloseBehavior.quit);
    await controller.show();
    await controller.quit();

    expect(calls.map((call) => call.method),
        ['setTitle', 'setTrayReady', 'setCloseBehavior', 'show', 'quit']);
    expect(calls.first.arguments, '(3) 工程群 - MagicChat');
    expect(calls[1].arguments, isTrue);
    expect(calls[2].arguments, 'quit');
  });
}

class _FakeDesktopWindowController implements DesktopWindowController {
  int showCount = 0;
  int quitCount = 0;
  bool trayReady = false;

  @override
  Future<void> show() async => showCount++;

  @override
  Future<void> quit() async => quitCount++;

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> setTrayReady(bool ready) async => trayReady = ready;

  @override
  Future<void> setCloseBehavior(DesktopCloseBehavior behavior) async {}
}
