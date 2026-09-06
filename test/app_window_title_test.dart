import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/app_window_title.dart';
import 'package:magicchat_client/data/app_window_title_platform.dart';
import 'package:magicchat_client/data/desktop_window_controller.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('标题状态组合总未读、会话或模块且提醒只看非静默未读', () {
    expect(
      const AppWindowTitleState(
        moduleTitle: '消息',
        conversationTitle: '工程群',
        totalUnread: 5,
        notifiableUnread: 3,
      ).pageTitle,
      '(5) 工程群 - MagicChat',
    );
    expect(
      const AppWindowTitleState(moduleTitle: '联系人').pageTitle,
      '联系人 - MagicChat',
    );
    expect(
      const AppWindowTitleState(
        moduleTitle: '设置',
        totalUnread: 2,
        notifiableUnread: 0,
      ).hasMessageAlert,
      isFalse,
    );
  });

  test('标题控制器去重更新并在释放时恢复应用名', () async {
    final platform = _FakeTitlePlatform();
    final controller = AppWindowTitleController(platform: platform);
    const state = AppWindowTitleState(
      moduleTitle: '项目',
      totalUnread: 4,
      notifiableUnread: 2,
    );

    await controller.update(state);
    await controller.update(state);
    expect(platform.updates, [(title: '(4) 项目 - MagicChat', alert: true)]);

    await controller.update(
      const AppWindowTitleState(moduleTitle: '项目'),
    );
    expect(platform.updates.last, (title: '项目 - MagicChat', alert: false));

    await controller.dispose();
    expect(platform.updates.last, (title: 'MagicChat', alert: false));
    expect(platform.disposeCount, 1);
  });

  test('平台 stub 仅在桌面调用窗口标题通道', () async {
    final window = _FakeDesktopWindowController();
    final platform = createAppWindowTitlePlatform(
      desktopWindowController: window,
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await platform.update(title: '消息 - MagicChat', alert: false);
    expect(window.titles, isEmpty);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await platform.update(title: '(2) 工程群 - MagicChat', alert: true);
    expect(window.titles, ['(2) 工程群 - MagicChat']);
  });

  testWidgets('AppShell 按会话、模块和实时未读更新安全标题', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1000, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = RealtimeStore();
    final platform = _FakeTitlePlatform();
    final controller = AppWindowTitleController(platform: platform);

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        repository: _TitleRepository(),
        realtimeStore: store,
        windowTitleController: controller,
      ),
    ));
    await tester.pumpAndSettle();
    expect(platform.updates.last.title, '消息 - MagicChat');

    await tester.tap(find.text('工程群'));
    await tester.pump();
    await tester.pump();
    expect(platform.updates.last.title, '工程群 - MagicChat');

    await tester.tap(find.text('联系人').last);
    await tester.pump();
    await tester.pump();
    expect(platform.updates.last.title, '联系人 - MagicChat');

    store.replaceConversation(const ChatConversation(
      id: 'group',
      title: '工程群',
      unread: 3,
      lastMessageSeq: 3,
    ));
    store.replaceConversation(const ChatConversation(
      id: 'muted',
      title: '静默群',
      unread: 2,
      muted: true,
      lastMessageSeq: 2,
    ));
    await tester.pump();
    await tester.pump();

    expect(platform.updates.last, (title: '(5) 联系人 - MagicChat', alert: true));
    expect(platform.updates.last.title, isNot(contains('消息正文')));
  });
}

class _FakeTitlePlatform implements AppWindowTitlePlatform {
  final updates = <({String title, bool alert})>[];
  int disposeCount = 0;

  @override
  Future<void> update({required String title, required bool alert}) async {
    updates.add((title: title, alert: alert));
  }

  @override
  Future<void> dispose() async => disposeCount++;
}

class _FakeDesktopWindowController implements DesktopWindowController {
  final titles = <String>[];

  @override
  Future<void> setTitle(String title) async => titles.add(title);

  @override
  Future<void> setCloseBehavior(DesktopCloseBehavior behavior) async {}

  @override
  Future<void> setTrayReady(bool ready) async {}

  @override
  Future<void> show() async {}

  @override
  Future<void> quit() async {}
}

class _TitleRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'group', title: '工程群', type: 'group'),
        ChatConversation(id: 'muted', title: '静默群', type: 'group'),
      ];
}
