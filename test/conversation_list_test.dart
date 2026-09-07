import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/conversation_draft_store.dart';
import 'package:magicchat_client/data/desktop_system_tray.dart';
import 'package:magicchat_client/data/last_conversation_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/main.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/domain/message_content.dart';
import 'package:magicchat_client/features/messages/conversation_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final dismissedConversationIds = <String>[];
  Completer<void>? dismissCompleter;

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

  @override
  Future<void> dismissConversation(String conversationId) {
    dismissedConversationIds.add(conversationId);
    return dismissCompleter?.future ?? Future.value();
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

class _NestedTopicRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
          id: 'parent-group',
          title: '产品群',
          type: 'group',
          lastMessageSeq: 3,
        ),
        ChatConversation(
          id: 'topic-1',
          title: '发布计划',
          type: 'topic',
          lastMessageSeq: 2,
          topic: TopicMetadata(
            archived: false,
            parentConversationId: 'parent-group',
            parentConversationName: '产品群',
            parentConversationType: 'group',
            participating: true,
            sourceMessageId: 'source-1',
            sourceMessageSeq: 1,
            sourceSender:
                TopicSourceSender(id: 'alice', type: 'user', name: 'Alice'),
          ),
        ),
      ];
}

class _ConversationPreviewRepository extends DemoRepository {
  var contactRequests = 0;

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
          id: 'preview-conversation',
          title: '预览会话',
          preview: '你好 {(@user/user-alice)}',
          members: [Contact(id: 'user-alice', name: 'Alice')],
        ),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async {
    contactRequests++;
    return const [Contact(id: 'unrelated', name: '不应加载')];
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

  testWidgets('进入消息页时恢复当前账号最近的有效会话', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'demo');
    await const LastConversationStore().write(scope, 'welcome');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
        home: AppShell(
            repository: DemoRepository(),
            serverUrl: 'https://chat.example.com')));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey('conversation-header-title')),
        findsOneWidget);
    expect(find.text('MagicChat 小助手'), findsWidgets);
  });

  testWidgets('打开会话后记住当前账号的最近会话', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'demo');
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
        home: AppShell(
            repository: DemoRepository(),
            serverUrl: 'https://chat.example.com')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MagicChat 小助手'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(await const LastConversationStore().read(scope), 'welcome');
  });

  testWidgets('最近会话已不存在时保持列表页并清理记录', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'demo');
    await const LastConversationStore().write(scope, 'missing');

    await tester.pumpWidget(MaterialApp(
        home: AppShell(
            repository: DemoRepository(),
            serverUrl: 'https://chat.example.com')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('conversation-header-title')), findsNothing);
    expect(await const LastConversationStore().read(scope), isEmpty);
  });

  test('会话预览只查找实际提及，不遍历 2000 个实时联系人', () {
    final contacts = _LookupOnlyContactMap({
      for (var index = 0; index < 2000; index++)
        'user-$index': Contact(id: 'user-$index', name: '成员 $index'),
    });
    const conversation = ChatConversation(
        id: 'large-preview',
        title: '大型组织群',
        preview: '请 {(@user/user-1999)} 查看');

    final labels = conversationPreviewMentionLabels(
            conversation.preview, conversation, contacts)
        .toList(growable: false);

    expect(formatMentionText(conversation.preview, labels), '请 @成员 1999 查看');
    expect(contacts.lookups, 1);
  });

  testWidgets('2000 人在线状态事件不重建会话托盘', (tester) async {
    final store = RealtimeStore();
    for (var index = 0; index < 2000; index++) {
      store.contacts['user-$index'] =
          Contact(id: 'user-$index', name: '成员 $index');
    }
    final tray = _CountingDesktopTray();
    await tester.pumpWidget(MaterialApp(
        home: AppShell(
            repository: _RealtimeConversationRepository(),
            realtimeStore: store,
            desktopTray: tray)));
    await tester.pumpAndSettle();
    final updatesBeforePresence = tray.updates;

    store.apply({
      'event': 'user.presence.updated',
      'cursor': 1,
      'payload': {'user_id': 'user-1999', 'online': true},
    });
    await tester.pump();

    expect(store.contacts['user-1999']?.online, isTrue);
    expect(tray.updates, updatesBeforePresence);
  });
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

  test('话题会话挂在对应父会话下并保留嵌套标记', () {
    const parent = ChatConversation(
        id: 'parent', title: '群聊', type: 'group', lastMessageSeq: 3);
    const topic = ChatConversation(
        id: 'topic',
        title: '话题',
        type: 'topic',
        topic: TopicMetadata(
            archived: false,
            parentConversationId: 'parent',
            parentConversationName: '群聊',
            parentConversationType: 'group',
            participating: true,
            sourceMessageId: 'source',
            sourceMessageSeq: 1,
            sourceSender:
                TopicSourceSender(id: 'alice', type: 'user', name: 'Alice')));
    final rows = buildConversationRows([topic, parent]);
    expect(rows.map((row) => row.conversation.id), ['parent', 'topic']);
    expect(rows.map((row) => row.nested), [false, true]);
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
        members: [Contact(id: 'user-alice', name: 'Alice')]);

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

  test('大小写变体 ID 不作为模型展示名称', () {
    expect(
        const ChatConversation(id: 'CONVERSATION-ID', title: 'conversation-id')
            .displayTitle,
        '私聊');
    expect(
        const MessageSearchResult(
                conversationId: 'CONVERSATION-ID',
                conversationName: 'conversation-id',
                message: ChatMessage(id: 'message-id', author: '', text: ''))
            .displayConversationName,
        '会话');
    expect(const ProjectUser(id: 'USER-ID', name: 'user-id').displayName, '成员');
    expect(
        const ProjectMember(
                id: 'USER-ID',
                name: 'user-id',
                displayNameOverride: 'User-Id',
                email: 'user@example.com')
            .displayName,
        'user@example.com');
    expect(
        const CurrentUser(id: 'USER-ID', name: 'user-id', email: 'USER-ID')
            .displayName,
        '用户');
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
            conversationId: 'c1',
            selectedConversationId: 'c2',
            eventMuted: true),
        isFalse);
    expect(
        shouldShowLocalMessageNotification(
            conversationId: 'c1',
            selectedConversationId: 'c2',
            senderType: 'system'),
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

  testWidgets('会话列表以层级展示父会话和话题', (tester) async {
    final repository = _NestedTopicRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessagesPage(
                repository: repository, selectedId: null, onSelect: (_) {}))));
    await tester.pumpAndSettle();

    expect(find.text('产品群'), findsOneWidget);
    expect(find.text('发布计划'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);
  });

  testWidgets('会话列表优先显示当前账号未发送的草稿', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-1');
    final drafts = ConversationDraftStore();
    await drafts.load(scope);
    drafts.update('welcome', text: '稍后继续', markdownMode: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessagesPage(
                repository: DemoRepository(),
                cacheScope: scope,
                draftStore: drafts,
                selectedId: null,
                onSelect: (_) {}))));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('[草稿] 稍后继续'), findsOneWidget);
    drafts.clear('welcome');
    await tester.pump();
    expect(find.text('[草稿] 稍后继续'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    drafts.dispose();
    await tester.pump();
  });

  testWidgets('从列表移除会话需确认且提交成功后清理草稿', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-1');
    final drafts = ConversationDraftStore();
    final repository = _PreferenceDemoRepository();
    await drafts.load(scope);
    drafts.update('preference', text: '不再保留', markdownMode: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessagesPage(
                repository: repository,
                cacheScope: scope,
                draftStore: drafts,
                selectedId: null,
                onSelect: (_) {}))));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.longPress(find.text('偏好会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从列表移除'));
    await tester.pumpAndSettle();

    expect(repository.dismissedConversationIds, isEmpty);
    expect(drafts.draftFor('preference'), isNotNull);
    expect(find.text('从列表移除对话？'), findsOneWidget);
    expect(find.textContaining('聊天记录不会删除，也不会退出群聊'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dismiss-conversation-cancel')));
    await tester.pumpAndSettle();
    expect(repository.dismissedConversationIds, isEmpty);
    expect(drafts.draftFor('preference'), isNotNull);

    repository.dismissCompleter = Completer<void>();
    await tester.longPress(find.text('偏好会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从列表移除'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('dismiss-conversation-confirm')));
    await tester.pump();

    expect(repository.dismissedConversationIds, ['preference']);
    expect(drafts.draftFor('preference'), isNotNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('dismiss-conversation-confirm')))
            .onPressed,
        isNull);

    repository.dismissCompleter!.complete();
    await tester.pumpAndSettle();
    expect(drafts.draftFor('preference'), isNull);
    expect(find.byKey(const ValueKey('dismiss-conversation-dialog')),
        findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    drafts.dispose();
    await tester.pump();
  });

  testWidgets('会话预览使用会话成员资料，不加载完整通讯录', (tester) async {
    final repository = _ConversationPreviewRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MessagesPage(
                repository: repository, selectedId: null, onSelect: (_) {}))));
    await tester.pumpAndSettle();

    expect(repository.contactRequests, 0);
    expect(find.text('你好 @Alice'), findsOneWidget);
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

class _LookupOnlyContactMap extends MapBase<String, Contact> {
  _LookupOnlyContactMap(this._values);

  final Map<String, Contact> _values;
  int lookups = 0;

  @override
  Contact? operator [](Object? key) {
    lookups++;
    return _values[key];
  }

  @override
  void operator []=(String key, Contact value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Iterable<String> get keys => throw StateError('不应遍历完整联系人 Map');

  @override
  Contact? remove(Object? key) => throw UnsupportedError('read only');
}

class _CountingDesktopTray implements DesktopSystemTrayController {
  int updates = 0;

  @override
  Future<bool> initialize(
          {required void Function(String conversationId)
              onOpenConversation}) async =>
      true;

  @override
  Future<void> update(
      {required int unreadCount,
      required Iterable<ChatConversation> conversations,
      required MessageNotificationPrivacy privacy,
      Map<String, Contact> contacts = const {}}) async {
    updates++;
  }

  @override
  Future<void> handleMenuAction(String? key) async {}

  @override
  Future<void> dispose() async {}
}
