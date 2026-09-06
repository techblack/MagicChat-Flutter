import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/conversation_announcement.dart';
import 'package:magicchat_client/main.dart';

void main() {
  testWidgets('长群公告默认限制三行并可展开收起', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const announcement = '第一行公告\n第二行公告\n第三行公告\n第四行公告\n第五行公告';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ConversationAnnouncement(announcement: announcement),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    Text text() => tester.widget<Text>(
        find.byKey(const ValueKey('conversation-announcement-text')));
    expect(text().data, announcement);
    expect(text().maxLines, 3);
    expect(find.text('展开'), findsOneWidget);

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(text().maxLines, isNull);
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(text().maxLines, 3);
  });

  testWidgets('群聊顶栏显示服务端成员数并在消息上方显示公告', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessagesPage(
          repository: _ContextRepository(),
          selectedId: 'group-1',
          onSelect: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('产品群 (8)'), findsOneWidget);
    expect(find.text('本周五 18:00 发布，请及时更新任务状态。'), findsOneWidget);
    expect(find.byKey(const ValueKey('conversation-announcement')),
        findsOneWidget);
  });

  testWidgets('大字号群公告正文与展开按钮上下分离', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ConversationAnnouncement(
            announcement: '第一行很长的群公告正文\n第二行正文\n第三行正文\n第四行正文',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final text = tester
        .getRect(find.byKey(const ValueKey('conversation-announcement-text')));
    final toggle = tester.getRect(
        find.byKey(const ValueKey('conversation-announcement-toggle')));
    expect(text.bottom, lessThanOrEqualTo(toggle.top));
  });
}

class _ContextRepository extends DemoRepository {
  static const conversation = ChatConversation(
    id: 'group-1',
    title: '产品群',
    type: 'group',
    memberCount: 8,
    announcement: '本周五 18:00 发布，请及时更新任务状态。',
    members: [
      Contact(id: 'alice', name: 'Alice'),
      Contact(id: 'bob', name: 'Bob'),
    ],
  );

  @override
  Future<List<ChatConversation>> conversations() async => const [conversation];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async =>
      conversation.members;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [];
}
