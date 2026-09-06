import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/asset_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/conversation_details_page.dart';
import 'package:magicchat_client/features/shared/cached_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('成员占位名称和大小写不同的 ID 会回退到可读资料', () {
    expect(
        const Contact(id: 'USER-1', name: '成员', email: 'user@example.com')
            .displayName,
        'user@example.com');
    expect(
        const Contact(
                id: 'ABCDEF12-3456-7890-ABCD-EF1234567890',
                name: 'abcdef12-3456-7890-abcd-ef1234567890',
                phone: '13800000000')
            .displayName,
        '13800000000');
    expect(
        const Contact(id: 'app-1', name: '成员', type: 'app').displayName, '成员');
  });

  testWidgets('群聊详情补齐当前群缺失的成员资料并使用可读备选名称', (tester) async {
    final repository = _DetailsRepository.incompleteMembers();
    const scope =
        MessageCacheScope(serverUrl: 'https://chat.example.com', userId: 'me');
    final avatarUri = Uri.parse('https://chat.example.com/avatars/alice.webp');
    final avatarCacheKey =
        'avatar|${scope.serverUrl}|${scope.userId}|$avatarUri';
    final avatarCache = LocalAssetCache();
    avatarCache.writeMemory(avatarCacheKey,
        Uint8List.fromList(image.encodePng(image.Image(width: 1, height: 1))));
    addTearDown(() => avatarCache.removeMemory(avatarCacheKey));
    final realtimeStore = RealtimeStore()
      ..contacts['user-alice'] = const Contact(
          id: 'user-alice',
          name: 'Alice',
          nickname: '小爱',
          avatar: '/avatars/alice.webp');
    await tester.pumpWidget(MaterialApp(
        home: ConversationDetailsPage(
      repository: repository,
      conversationId: repository.conversation.id,
      initialConversation: repository.conversation,
      serverUrl: 'https://chat.example.com',
      cacheScope: scope,
      realtimeStore: realtimeStore,
    )));
    await tester.pumpAndSettle();

    expect(
        repository.resolvedUserIds, ['me', 'user-bob', 'charlie', 'user-dana']);
    expect(repository.contactRequests, 0);
    expect(find.text('小爱'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('charlie@example.com'), findsOneWidget);
    expect(find.text('Dana'), findsOneWidget);
    expect(find.text('成员'), findsNothing);
    final alice = tester.widget<CachedAvatar>(find.byWidgetPredicate(
        (widget) => widget is CachedAvatar && widget.name == '小爱'));
    expect(alice.avatarUri, avatarUri);
  });

  testWidgets('大群分块补齐时单个失败不影响其他成员', (tester) async {
    final repository = _DetailsRepository.partiallyResolvableGroup();

    await _pumpDetails(tester, repository);

    expect(repository.resolvedUserBatches.map((ids) => ids.length), [100, 1]);
    expect(find.text('最后一位成员'), findsOneWidget);
  });

  testWidgets('群主可以在聊天详情关联和解除项目', (tester) async {
    final repository = _DetailsRepository.group('owner', projects: const [
      Project(id: '1', name: 'MagicChat Flutter 重构'),
    ]);
    await _pumpDetails(tester, repository);

    expect(find.text('关联项目（1）'), findsOneWidget);
    expect(find.text('MagicChat Flutter 重构'), findsOneWidget);
    await tester.tap(find.byTooltip('关联项目'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('产品迭代'), findsOneWidget);
    final projectTile = find.widgetWithText(ListTile, '产品迭代');
    await tester.tap(projectTile);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '关联'));
    await tester.pumpAndSettle();
    expect(repository.conversation.projects.map((project) => project.name),
        contains('产品迭代'));

    await tester.tap(find.byTooltip('解除关联').last);
    await tester.pumpAndSettle();
    expect(find.text('解除项目关联？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '解除关联'));
    await tester.pumpAndSettle();
    expect(repository.conversation.projects.map((project) => project.name),
        isNot(contains('产品迭代')));
  });

  testWidgets('群主可在聊天详情管理资料、偏好和成员', (tester) async {
    final repository = _DetailsRepository.group('owner');
    await _pumpDetails(tester, repository);

    expect(find.text('聊天信息 (3)'), findsOneWidget);
    expect(find.text('当前用户'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('演示应用'), findsOneWidget);
    expect(find.text('群聊名称'), findsOneWidget);
    expect(find.text('群公告'), findsOneWidget);
    expect(find.text('公开群聊'), findsOneWidget);
    expect(find.text('解散群聊'), findsOneWidget);

    await tester.tap(find.text('群聊名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新群名称');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.conversation.title, '新群名称');
    expect(find.text('新群名称'), findsOneWidget);

    final mute = find.widgetWithText(SwitchListTile, '消息免打扰');
    await tester.tap(mute);
    await tester.pumpAndSettle();
    expect(repository.conversation.muted, isTrue);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Bob'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Alice'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Bob'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    expect(repository.conversation.members.map((member) => member.id),
        contains('user-bob'));
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('普通群成员只能添加成员并退出群聊', (tester) async {
    final repository = _DetailsRepository.group('member');
    var removed = false;
    await _pumpDetails(tester, repository,
        onConversationRemoved: () => removed = true);

    expect(find.text('群聊名称'), findsOneWidget);
    expect(find.text('群公告'), findsOneWidget);
    expect(find.text('群头像'), findsNothing);
    expect(find.text('公开群聊'), findsNothing);
    expect(find.text('移除'), findsNothing);
    expect(find.text('退出群聊'), findsOneWidget);

    await tester.tap(find.text('退出群聊'));
    await tester.pumpAndSettle();
    expect(find.text('确认退出群聊？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认退出'));
    await tester.pumpAndSettle();
    expect(repository.left, isTrue);
    expect(removed, isTrue);
  });

  testWidgets('私聊详情预选对方并可追加联系人创建群聊', (tester) async {
    final repository = _DetailsRepository.direct();
    String? opened;
    await _pumpDetails(tester, repository,
        onOpenConversation: (id) => opened = id);

    expect(find.text('聊天详情'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final alice = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Alice'));
    expect(alice.value, isTrue);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Bob'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();

    expect(repository.createdName, '新建群聊');
    expect(
        repository.createdMemberIds, containsAll(['user-alice', 'user-bob']));
    expect(opened, 'created-group');
  });

  testWidgets('话题详情可按服务端权限关闭话题', (tester) async {
    final repository = _DetailsRepository.topic();
    await _pumpDetails(tester, repository);

    expect(find.text('话题详情'), findsOneWidget);
    expect(find.text('关闭话题'), findsOneWidget);
    await tester.tap(find.text('关闭话题'));
    await tester.pumpAndSettle();
    expect(find.text('关闭话题？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '关闭话题'));
    await tester.pumpAndSettle();

    expect(repository.conversation.topic?.archived, isTrue);
    expect(find.text('关闭话题'), findsNothing);
  });

  testWidgets('聊天详情页面视觉基线', (tester) async {
    final repository = _DetailsRepository.group('owner');
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('conversation-details-golden'),
      child: SizedBox(
        width: 600,
        height: 900,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ConversationDetailsPage(
              repository: repository,
              conversationId: repository.conversation.id,
              initialConversation: repository.conversation),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('conversation-details-golden')),
      matchesGoldenFile('evidence/conversation_details.png'),
    );
  });
}

Future<void> _pumpDetails(WidgetTester tester, _DetailsRepository repository,
    {ValueChanged<String>? onOpenConversation,
    VoidCallback? onConversationRemoved}) async {
  await tester.binding.setSurfaceSize(const Size(600, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      home: ConversationDetailsPage(
    repository: repository,
    conversationId: repository.conversation.id,
    initialConversation: repository.conversation,
    onOpenConversation: onOpenConversation,
    onConversationRemoved: onConversationRemoved,
  )));
  await tester.pumpAndSettle();
}

class _DetailsRepository extends DemoRepository {
  _DetailsRepository._(this.conversation,
      {this.failFullResolutionBatch = false});

  factory _DetailsRepository.group(String role,
          {List<Project> projects = const []}) =>
      _DetailsRepository._(
        ChatConversation(
          id: 'group',
          title: '工程群',
          announcement: '欢迎加入工程群',
          type: 'group',
          isPublic: false,
          members: [
            Contact(id: 'me', name: '当前用户', role: role),
            const Contact(
                id: 'user-alice', name: 'Alice', email: 'alice@example.com'),
            const Contact(id: 'app', name: '演示应用', type: 'app'),
          ],
          projects: projects,
        ),
      );

  factory _DetailsRepository.direct() => _DetailsRepository._(
        const ChatConversation(
          id: 'direct',
          title: 'Alice',
          type: 'direct',
          members: [
            Contact(id: 'me', name: '当前用户'),
            Contact(
                id: 'user-alice', name: 'Alice', email: 'alice@example.com'),
          ],
        ),
      );

  factory _DetailsRepository.incompleteMembers() => _DetailsRepository._(
        const ChatConversation(
          id: 'group-incomplete',
          title: '大群',
          type: 'group',
          members: [
            Contact(id: 'me', name: '当前用户', role: 'owner'),
            Contact(id: 'user-alice', name: ''),
            Contact(id: 'user-bob', name: '成员'),
            Contact(id: 'charlie', name: ''),
            Contact(
                id: 'user-dana',
                name: '成员',
                email: 'dana@example.com',
                avatar: '/avatars/dana.webp'),
          ],
        ),
      );

  factory _DetailsRepository.partiallyResolvableGroup() => _DetailsRepository._(
        ChatConversation(
          id: 'group-partial-resolution',
          title: '大群',
          type: 'group',
          members: [
            const Contact(id: 'me', name: '当前用户', role: 'owner'),
            for (var index = 0; index < 100; index++)
              Contact(id: 'member-$index', name: ''),
          ],
        ),
        failFullResolutionBatch: true,
      );

  factory _DetailsRepository.topic() => _DetailsRepository._(
        const ChatConversation(
          id: 'topic',
          title: '发布讨论',
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
                  TopicSourceSender(id: 'alice', type: 'user', name: 'Alice')),
        ),
      );

  ChatConversation conversation;
  bool left = false;
  String? createdName;
  List<String> createdMemberIds = const [];
  List<String> resolvedUserIds = const [];
  final List<List<String>> resolvedUserBatches = [];
  final bool failFullResolutionBatch;
  int contactRequests = 0;

  @override
  Future<void> bindConversationProject(
      String conversationId, String projectId) async {
    final project =
        (await projects()).firstWhere((item) => item.id == projectId);
    conversation = _copy(projects: [...conversation.projects, project]);
  }

  @override
  Future<void> unbindConversationProject(
      String conversationId, String projectId) async {
    conversation = _copy(
        projects: conversation.projects
            .where((project) => project.id != projectId)
            .toList(growable: false));
  }

  @override
  Future<CurrentUser> currentUser() async =>
      const CurrentUser(id: 'me', name: '当前用户', email: 'me@example.com');

  @override
  Future<List<ChatConversation>> conversations() async => [conversation];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async {
    contactRequests++;
    return const [
      Contact(id: 'user-alice', name: 'Alice', email: 'alice@example.com'),
      Contact(id: 'user-bob', name: 'Bob', email: 'bob@example.com'),
    ];
  }

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async {
    resolvedUserIds = List.of(userIds);
    resolvedUserBatches.add(List.of(userIds));
    if (failFullResolutionBatch && userIds.length == 100) {
      throw StateError('该分块资料加载失败');
    }
    if (failFullResolutionBatch) {
      return [
        for (final id in userIds) Contact(id: id, name: '最后一位成员'),
      ];
    }
    if (conversation.id != 'group-incomplete') return const [];
    return [
      if (userIds.contains('user-alice'))
        const Contact(
            id: 'user-alice',
            name: 'Alice',
            nickname: '小爱',
            avatar: '/avatars/alice.webp'),
      if (userIds.contains('user-bob'))
        const Contact(id: 'user-bob', name: 'Bob'),
      if (userIds.contains('charlie'))
        const Contact(id: 'charlie', name: '', email: 'charlie@example.com'),
      if (userIds.contains('user-dana'))
        const Contact(
            id: 'user-dana', name: 'Dana', avatar: '/avatars/dana.webp'),
    ];
  }

  @override
  Future<Uint8List?> downloadResource(Uri uri) async =>
      Uint8List.fromList(image.encodePng(image.Image(width: 1, height: 1)));

  @override
  Future<void> renameGroupConversation(
      String conversationId, String name) async {
    conversation = _copy(title: name);
  }

  @override
  Future<void> updateGroupAnnouncement(
      String conversationId, String announcement) async {
    conversation = _copy(announcement: announcement);
  }

  @override
  Future<void> setGroupVisibility(String conversationId, bool isPublic) async {
    conversation = _copy(isPublic: isPublic);
  }

  @override
  Future<bool> setConversationMuted(String conversationId, bool muted) async {
    conversation = _copy(muted: muted);
    return muted;
  }

  @override
  Future<bool> setConversationPinned(String conversationId, bool pinned) async {
    conversation = _copy(pinned: pinned);
    return pinned;
  }

  @override
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {
    final contactsById = {
      for (final contact in await contacts()) contact.id: contact
    };
    conversation = _copy(members: [
      ...conversation.members,
      for (final id in memberIds)
        if (!conversation.members.any((member) => member.id == id))
          contactsById[id]!,
    ]);
  }

  @override
  Future<void> removeConversationMember(String conversationId, String memberId,
      {String memberType = 'user'}) async {
    conversation = _copy(
        members: conversation.members
            .where((member) => member.id != memberId)
            .toList(growable: false));
  }

  @override
  Future<void> leaveGroupConversation(String conversationId) async {
    left = true;
  }

  @override
  Future<TopicDetail> topicDetail(String conversationId) async => TopicDetail(
      canArchive: true,
      canParticipate: false,
      conversation: conversation,
      parentConversation: const TopicReference(id: 'group', name: '工程群'),
      sourceMessage: const TopicSourceMessage(
          id: 'message',
          createdAt: '2026-09-05T00:00:00Z',
          sender: TopicSourceSender(id: 'alice', type: 'user', name: 'Alice'),
          sequence: 1,
          summary: '发布讨论',
          body: {'type': 'text', 'content': '发布讨论'}));

  @override
  Future<ChatConversation> archiveTopic(String conversationId) async {
    final topic = conversation.topic!;
    conversation = ChatConversation(
      id: conversation.id,
      title: conversation.title,
      type: conversation.type,
      pinned: conversation.pinned,
      muted: conversation.muted,
      topic: TopicMetadata(
          archived: true,
          parentConversationId: topic.parentConversationId,
          parentConversationName: topic.parentConversationName,
          parentConversationType: topic.parentConversationType,
          participating: topic.participating,
          sourceMessageId: topic.sourceMessageId,
          sourceMessageSeq: topic.sourceMessageSeq,
          sourceSender: topic.sourceSender),
    );
    return conversation;
  }

  @override
  Future<ChatConversation> createGroupConversation(String name,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {
    createdName = name;
    createdMemberIds = memberIds;
    return const ChatConversation(
        id: 'created-group', title: '新建群聊', type: 'group');
  }

  ChatConversation _copy({
    String? title,
    String? announcement,
    bool? isPublic,
    bool? muted,
    bool? pinned,
    List<Contact>? members,
    List<Project>? projects,
  }) =>
      ChatConversation(
        id: conversation.id,
        title: title ?? conversation.title,
        preview: conversation.preview,
        announcement: announcement ?? conversation.announcement,
        isPublic: isPublic ?? conversation.isPublic,
        avatar: conversation.avatar,
        createdAt: conversation.createdAt,
        unread: conversation.unread,
        pinned: pinned ?? conversation.pinned,
        muted: muted ?? conversation.muted,
        lastMessageAt: conversation.lastMessageAt,
        lastMessageSeq: conversation.lastMessageSeq,
        lastReadSeq: conversation.lastReadSeq,
        lastMentionedSeq: conversation.lastMentionedSeq,
        lastChoiceSeq: conversation.lastChoiceSeq,
        type: conversation.type,
        members: members ?? conversation.members,
        projects: projects ?? conversation.projects,
        canSend: conversation.canSend,
        topic: conversation.topic,
      );
}
