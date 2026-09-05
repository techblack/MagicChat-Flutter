import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/main.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/conversation_list.dart';

class _MentionDemoRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
            id: 'mention',
            title: '提及我的群聊',
            preview: '有人在消息中提及你',
            type: 'group',
            lastMessageSeq: 5,
            lastReadSeq: 2,
            lastMentionedSeq: 5),
      ];
}

class _RefreshDemoRepository extends DemoRepository {
  var requests = 0;

  @override
  Future<List<ChatConversation>> conversations() async {
    requests++;
    return super.conversations();
  }
}

class _PreferenceDemoRepository extends DemoRepository {
  var pinned = false;
  var muted = false;

  @override
  Future<List<ChatConversation>> conversations() async => [
        ChatConversation(
            id: 'preference',
            title: '偏好会话',
            preview: '测试置顶和静默',
            pinned: pinned,
            muted: muted),
      ];

  @override
  Future<bool> setConversationPinned(String conversationId, bool value) async {
    pinned = value;
    return value;
  }

  @override
  Future<bool> setConversationMuted(String conversationId, bool value) async {
    muted = value;
    return value;
  }
}

class _RealtimeConversationRepository extends DemoRepository {
  var requests = 0;

  @override
  Future<List<ChatConversation>> conversations() async {
    requests++;
    return const [
      ChatConversation(
          id: 'older',
          title: '旧会话',
          lastMessageAt: '2026-09-04T10:00:00Z',
          lastMessageSeq: 1),
      ChatConversation(
          id: 'newer',
          title: '新会话',
          lastMessageAt: '2026-09-04T11:00:00Z',
          lastMessageSeq: 2),
    ];
  }
}

class _MarkAllReadRepository extends DemoRepository {
  final readIds = <String>[];
  final readSequences = <String, int>{};

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
            id: 'unread-a',
            title: '未读会话 A',
            unread: 2,
            lastMessageSeq: 8,
            lastReadSeq: 6),
        ChatConversation(
            id: 'unread-b',
            title: '未读会话 B',
            lastMessageSeq: 4,
            lastReadSeq: 1,
            lastChoiceSeq: 9),
      ];

  @override
  Future<ConversationReadResult> markConversationRead(
      String conversationId, int upToSeq) async {
    readIds.add(conversationId);
    readSequences[conversationId] = upToSeq;
    return ConversationReadResult(
        conversationId: conversationId, lastReadSeq: upToSeq, unreadCount: 0);
  }
}

void main() {
  const direct = ChatConversation(
      id: 'direct',
      title: 'Alice',
      type: 'direct',
      lastMessageSeq: 4,
      lastReadSeq: 4);
  const unreadGroup = ChatConversation(
      id: 'group', title: '工程群', type: 'group', unread: 2, lastMessageSeq: 8);
  const pinnedApp = ChatConversation(
      id: 'app', title: '助手', type: 'app', pinned: true, lastMessageSeq: 1);
  const choiceUnread = ChatConversation(
      id: 'choice', title: '选择题', lastMessageSeq: 4, lastChoiceSeq: 5);
  const mentionUnread = ChatConversation(
      id: 'mention', title: '提及', lastMessageSeq: 6, lastMentionedSeq: 7);

  test('置顶优先，其余按最新消息序号倒序并保持稳定', () {
    expect(
        orderConversations([direct, pinnedApp, unreadGroup])
            .map((item) => item.id),
        ['app', 'group', 'direct']);
  });

  test('有最后消息时间时按时间倒序排列', () {
    final values = orderConversations(const [
      ChatConversation(
          id: 'older',
          title: '旧会话',
          lastMessageAt: '2026-09-04T10:00:00Z',
          lastMessageSeq: 99),
      ChatConversation(
          id: 'newer',
          title: '新会话',
          lastMessageAt: '2026-09-04T11:00:00Z',
          lastMessageSeq: 1),
    ]);
    expect(values.map((item) => item.id), ['newer', 'older']);
  });

  test('资料缺失时使用可读占位，会话优先使用成员名称', () {
    const contact = Contact(id: 'user-raw-id', name: 'user-raw-id');
    const projectUser = ProjectUser(id: 'project-user-id');
    const conversation = ChatConversation(
        id: 'conversation-id',
        title: 'conversation-id',
        members: [Contact(id: 'alice', name: 'Alice')]);

    expect(contact.displayName, '成员');
    expect(projectUser.displayName, '成员');
    expect(
        const CurrentUser(
                id: 'user-raw-id',
                name: 'user-raw-id',
                email: 'user@example.com')
            .displayName,
        'user@example.com');
    expect(conversation.displayTitle, 'Alice');
    expect(
        const MessageSearchResult(
                conversationId: 'conversation-id',
                conversationName: 'conversation-id',
                message: ChatMessage(id: 'message-id', author: '', text: ''))
            .displayConversationName,
        '会话');
  });

  test('导航未读数包含普通未读和独立提醒', () {
    const conversations = [
      ChatConversation(id: 'normal', title: '普通', unread: 3),
      ChatConversation(
          id: 'mention', title: '提及', lastReadSeq: 4, lastMentionedSeq: 6),
      ChatConversation(
          id: 'covered',
          title: '已计数提醒',
          unread: 2,
          lastReadSeq: 4,
          lastChoiceSeq: 6),
      ChatConversation(
          id: 'sequence', title: '序号未读', lastMessageSeq: 8, lastReadSeq: 7),
    ];

    expect(totalConversationUnread(conversations), 7);
  });

  test('未读和类型筛选按话题父会话类型匹配', () {
    const topic = ChatConversation(
        id: 'topic',
        title: '群话题',
        type: 'topic',
        topic: TopicMetadata(
            archived: false,
            parentConversationId: 'group',
            parentConversationName: '工程群',
            parentConversationType: 'group',
            participating: true,
            sourceMessageId: 'message',
            sourceMessageSeq: 1,
            sourceSender:
                TopicSourceSender(id: 'sender', type: 'user', name: '成员')));

    expect(matchesConversationFilter(unreadGroup, ConversationFilter.unread),
        isTrue);
    expect(
        matchesConversationFilter(direct, ConversationFilter.unread), isFalse);
    expect(matchesConversationFilter(topic, ConversationFilter.group), isTrue);
    expect(
        matchesConversationFilter(topic, ConversationFilter.direct), isFalse);
    expect(matchesConversationFilter(pinnedApp, ConversationFilter.direct),
        isTrue);
    expect(matchesConversationFilter(choiceUnread, ConversationFilter.unread),
        isTrue);
    expect(matchesConversationFilter(mentionUnread, ConversationFilter.unread),
        isTrue);
    expect(conversationReadTargetSequence(choiceUnread), 5);
    expect(conversationReadTargetSequence(mentionUnread), 7);
  });

  test('搜索标题、预览和公告，忽略大小写', () {
    const conversation =
        ChatConversation(id: 'group', title: '工程群', preview: 'Release Ready');
    expect(matchesConversationQuery(conversation, 'release'), isTrue);
    expect(matchesConversationQuery(conversation, '  工程 '), isTrue);
    expect(matchesConversationQuery(conversation, '不存在'), isFalse);
  });

  test('消息时间按本地时间格式化并显示日期边界', () {
    final now = DateTime(2026, 9, 4, 12, 0);
    expect(
        formatMessageTime(DateTime(2026, 9, 4, 9, 5).toUtc().toIso8601String(),
            now: now),
        '09:05');
    expect(
        formatMessageTime(DateTime(2026, 9, 3, 9, 5).toUtc().toIso8601String(),
            now: now),
        '09-03 09:05');
    expect(formatMessageTime('not-a-date'), isNull);
  });

  test('静默会话不触发本地消息通知', () {
    expect(
        shouldShowLocalMessageNotification(
            conversationId: 'c1', selectedConversationId: 'c2', muted: true),
        isFalse);
    expect(
        shouldShowLocalMessageNotification(
            conversationId: 'c1', selectedConversationId: 'c1'),
        isFalse);
    expect(
        shouldShowLocalMessageNotification(
            conversationId: 'c1', selectedConversationId: 'c2'),
        isTrue);
    expect(
        shouldShowLocalMessageNotification(
            conversationId: 'c1',
            selectedConversationId: 'c2',
            senderId: 'me',
            currentUserId: 'me'),
        isFalse);
  });

  test('会话响应解析提及和选择提醒序号', () {
    final conversation = ChatConversation.fromJson({
      'id': 'c1',
      'name': '工程群',
      'last_message_seq': 8,
      'created_at': '2026-09-03T10:00:00Z',
      'last_message_at': '2026-09-04T10:00:00Z',
      'last_read_seq': 3,
      'last_mentioned_seq': 6,
      'last_choice_seq': 7,
    });
    expect(conversation.lastMentionedSeq, 6);
    expect(conversation.lastChoiceSeq, 7);
    expect(conversation.lastMessageAt, '2026-09-04T10:00:00Z');
  });

  testWidgets('会话列表支持未读筛选和关键词搜索', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: DemoRepository())));
    await tester.pumpAndSettle();

    expect(find.text('MagicChat 小助手'), findsOneWidget);
    expect(find.text('团队群聊'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '未读'));
    await tester.pumpAndSettle();
    expect(find.text('团队群聊'), findsOneWidget);
    expect(find.text('MagicChat 小助手'), findsNothing);

    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的会话'), findsOneWidget);
  });

  testWidgets('会话列表支持下拉刷新并保留内容', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _RefreshDemoRepository();
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();
    final requestsBeforeRefresh = repository.requests;
    expect(requestsBeforeRefresh, greaterThanOrEqualTo(1));

    await tester.drag(find.text('MagicChat 小助手'), const Offset(0, 420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(repository.requests, requestsBeforeRefresh + 1);
    expect(find.text('MagicChat 小助手'), findsOneWidget);
  });

  testWidgets('会话可以置顶并开启静默', (tester) async {
    final repository = _PreferenceDemoRepository();
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('偏好会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶会话'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.longPress(find.text('偏好会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息免打扰'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_off), findsOneWidget);
  });

  testWidgets('会话列表可将所有未读会话一次标为已读', (tester) async {
    final repository = _MarkAllReadRepository();
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('全部标为已读'));
    await tester.pumpAndSettle();

    expect(repository.readIds, containsAll(<String>['unread-a', 'unread-b']));
    expect(repository.readSequences['unread-b'], 9);
    expect(find.text('已将 2 个会话标为已读'), findsOneWidget);
  });

  testWidgets('实时新消息原地更新会话而不重新请求列表', (tester) async {
    final repository = _RealtimeConversationRepository();
    final store = RealtimeStore()..currentUserId = 'me';
    await tester.pumpWidget(MaterialApp(
        home: AppShell(repository: repository, realtimeStore: store)));
    await tester.pumpAndSettle();
    final requestsBeforeEvent = repository.requests;
    expect(requestsBeforeEvent, greaterThanOrEqualTo(1));

    store.apply({
      'event': 'message.created',
      'cursor': 1,
      'payload': {
        'id': 'm3',
        'conversation_id': 'older',
        'seq': 3,
        'created_at': '2026-09-04T12:00:00Z',
        'sender': {'id': 'other', 'name': '其他成员'},
        'body': {'type': 'text', 'content': '刚刚收到'},
      }
    });
    await tester.pump();

    expect(repository.requests, requestsBeforeEvent);
    expect(find.text('刚刚收到'), findsOneWidget);
    final tiles = find.byType(ListTile);
    expect((tester.widget<ListTile>(tiles.first).title as Text).data, '旧会话');
  });

  testWidgets('生成会话筛选流程截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('conversation-filters-golden'),
      child: SizedBox(
        width: 900,
        height: 700,
        child: MaterialApp(home: AppShell(repository: DemoRepository())),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '未读'));
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const ValueKey('conversation-filters-golden')),
        matchesGoldenFile('evidence/conversation_filters.png'));
  });

  testWidgets('会话列表显示提及提醒标记', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('conversation-mention-golden'),
      child: SizedBox(
        width: 900,
        height: 700,
        child:
            MaterialApp(home: AppShell(repository: _MentionDemoRepository())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.alternate_email), findsOneWidget);
    await expectLater(find.byKey(const ValueKey('conversation-mention-golden')),
        matchesGoldenFile('evidence/conversation_mention.png'));
  });
}
