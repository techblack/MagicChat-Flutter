import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/asset_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/domain/user_safety.dart';
import 'package:magicchat_client/features/messages/conversation_details_page.dart';
import 'package:magicchat_client/features/shared/cached_avatar.dart';
import 'package:magicchat_client/features/shared/conversation_avatar.dart';
import 'package:magicchat_client/features/shared/custom_avatar_picker.dart';
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
    final alice = tester.widget<CachedAvatar>(find.byWidgetPredicate((widget) =>
        widget is CachedAvatar && widget.name == '小爱' && widget.radius == 22));
    expect(alice.avatarUri, avatarUri);

    realtimeStore.lastEvent = 'user.profile.updated';
    realtimeStore.replaceUserProfile(const Contact(
        id: 'user-alice', name: 'Alice', nickname: '新小爱', avatar: ''));
    await tester.pumpAndSettle();
    expect(find.text('新小爱'), findsOneWidget);
    expect(find.text('小爱'), findsNothing);
  });

  testWidgets('大群分块补齐时单个失败不影响其他成员', (tester) async {
    final repository = _DetailsRepository.partiallyResolvableGroup();

    await _pumpDetails(tester, repository);

    expect(repository.resolvedUserBatches.map((ids) => ids.length), [100, 1]);
    expect(find.text('最后一位成员'), findsOneWidget);
  });

  testWidgets('服务端未返回群成员资料时明确提示并可重试', (tester) async {
    final repository = _DetailsRepository.unavailableMember();

    await _pumpDetails(tester, repository);

    expect(repository.resolvedUserBatches, [
      ['user-disabled']
    ]);
    expect(find.text('资料不可用'), findsOneWidget);
    expect(find.text('1 位成员已停用或资料暂不可用'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(repository.resolvedUserBatches, hasLength(2));

    await tester.tap(find.text('资料不可用'));
    await tester.pumpAndSettle();
    expect(find.text('该成员可能已停用，或资料暂时无法加载。'), findsOneWidget);
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

  testWidgets('点击已关联项目先关闭聊天详情再打开项目', (tester) async {
    final repository = _DetailsRepository.group('member', projects: const [
      Project(id: 'project-1', name: '产品迭代'),
    ]);
    late BuildContext hostContext;
    String? openedProjectId;
    bool? detailsStillOpen;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        hostContext = context;
        return Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ConversationDetailsPage(
                  repository: repository,
                  conversationId: repository.conversation.id,
                  initialConversation: repository.conversation,
                  onOpenProject: (projectId) {
                    openedProjectId = projectId;
                    detailsStillOpen = Navigator.canPop(hostContext);
                  },
                ),
              ),
            ),
            child: const Text('打开聊天详情'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('打开聊天详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('产品迭代'));
    await tester.pumpAndSettle();

    expect(openedProjectId, 'project-1');
    expect(detailsStillOpen, isFalse);
    expect(find.text('打开聊天详情'), findsOneWidget);
  });

  testWidgets('普通群成员可在详情查看成员组合群头像', (tester) async {
    final repository = _DetailsRepository.group('member');

    await _pumpDetails(tester, repository);

    final tile = find.widgetWithText(ListTile, '群头像');
    expect(tile, findsOneWidget);
    expect(find.descendant(of: tile, matching: find.byType(ConversationAvatar)),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('group-avatar-member-me')), findsOneWidget);
    expect(tester.widget<ListTile>(tile).onTap, isNull);
  });

  testWidgets('群主拖动缩放裁剪群头像并确认上传', (tester) async {
    final source = image.Image(width: 400, height: 200);
    final sourceBytes = Uint8List.fromList(image.encodePng(source));
    final repository = _DetailsRepository.group('owner',
        avatar: 'https://chat.example.com/avatars/group.webp');

    await _pumpDetails(
      tester,
      repository,
      serverUrl: 'https://chat.example.com',
      avatarImagePicker: () async =>
          AvatarPickerImage(name: 'group.png', bytes: sourceBytes),
    );

    var avatar =
        tester.widget<ConversationAvatar>(find.byType(ConversationAvatar));
    expect(avatar.conversation.avatar,
        'https://chat.example.com/avatars/group.webp');
    var renderedAvatar = tester.widget<CachedAvatar>(find.descendant(
        of: find.byType(ConversationAvatar),
        matching: find.byType(CachedAvatar)));
    expect(renderedAvatar.avatarUri,
        Uri.parse('https://chat.example.com/avatars/group.webp'));

    await tester.tap(find.text('群头像'));
    await tester.pumpAndSettle();
    expect(find.text('修改群头像'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-avatar-pick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-avatar-crop')), findsOneWidget);
    expect(repository.uploadedAvatarBytes, isNull);

    final zoom = find.byKey(const ValueKey('group-avatar-zoom'));
    await tester.drag(zoom, const Offset(80, 0));
    await tester.pump();
    expect(tester.widget<Slider>(zoom).value, greaterThan(1));
    await tester.drag(
        find.byKey(const ValueKey('group-avatar-crop')), const Offset(-30, 0));
    await tester.pump();
    final save = find.byKey(const ValueKey('group-avatar-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final uploaded = image.decodeWebP(repository.uploadedAvatarBytes!);
    expect(uploaded, isNotNull);
    expect(uploaded!.width, 256);
    expect(uploaded.height, 256);
    expect(find.text('修改群头像'), findsNothing);
    avatar = tester.widget<ConversationAvatar>(find.byType(ConversationAvatar));
    expect(avatar.conversation.avatar,
        'https://chat.example.com/avatars/group-updated.webp');
    renderedAvatar = tester.widget<CachedAvatar>(find.descendant(
        of: find.byType(ConversationAvatar),
        matching: find.byType(CachedAvatar)));
    expect(renderedAvatar.avatarUri,
        Uri.parse('https://chat.example.com/avatars/group-updated.webp'));
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

  testWidgets('详情页切换群公开状态需确认并在成功后刷新', (tester) async {
    final repository = _DetailsRepository.group('owner');
    await _pumpDetails(tester, repository);

    var visibility = find.widgetWithText(SwitchListTile, '公开群聊');
    expect(tester.widget<SwitchListTile>(visibility).value, isFalse);
    await tester.tap(visibility);
    await tester.pumpAndSettle();

    expect(find.text('设为公开群聊？'), findsOneWidget);
    expect(find.textContaining('所有用户都可以在通讯录中发现并加入'), findsOneWidget);
    expect(repository.visibilityChanges, isEmpty);
    await tester.tap(find.byKey(const ValueKey('group-visibility-cancel')));
    await tester.pumpAndSettle();
    visibility = find.widgetWithText(SwitchListTile, '公开群聊');
    expect(tester.widget<SwitchListTile>(visibility).value, isFalse);
    expect(repository.visibilityChanges, isEmpty);

    repository.visibilityCompleter = Completer<void>();
    await tester.tap(visibility);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-visibility-confirm')));
    await tester.pump();

    expect(repository.visibilityChanges, [true]);
    visibility = find.widgetWithText(SwitchListTile, '公开群聊');
    expect(tester.widget<SwitchListTile>(visibility).value, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('group-visibility-confirm')))
            .onPressed,
        isNull);

    repository.visibilityCompleter!.complete();
    await tester.pumpAndSettle();
    visibility = find.widgetWithText(SwitchListTile, '公开群聊');
    expect(tester.widget<SwitchListTile>(visibility).value, isTrue);
  });

  testWidgets('点击群成员可查看完整资料并发起私聊', (tester) async {
    final repository = _DetailsRepository.group('owner');
    String? openedConversationId;
    await _pumpDetails(tester, repository,
        onOpenConversation: (id) => openedConversationId = id);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('联系人详情'), findsOneWidget);
    expect(find.text('用户资料'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发消息'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '发消息'));
    await tester.pumpAndSettle();
    expect(openedConversationId, 'user-alice');
  });

  testWidgets('群主可从应用分组邀请应用进入群聊', (tester) async {
    final repository = _DetailsRepository.group('owner');
    await _pumpDetails(tester, repository);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, '自动化助手'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, '自动化助手'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();

    expect(repository.addedMemberIds, isEmpty);
    expect(repository.addedAppIds, ['app-helper']);
    expect(repository.conversation.members.map((member) => member.id),
        contains('app-helper'));
  });

  testWidgets('普通群成员只能添加成员并退出群聊', (tester) async {
    final repository = _DetailsRepository.group('member');
    var removed = false;
    await _pumpDetails(tester, repository,
        onConversationRemoved: () => removed = true);

    expect(find.text('群聊名称'), findsOneWidget);
    expect(find.text('群公告'), findsOneWidget);
    expect(find.text('群头像'), findsOneWidget);
    expect(find.text('公开群聊'), findsNothing);
    expect(find.text('移除'), findsNothing);
    expect(find.text('退出群聊'), findsOneWidget);

    await tester.tap(find.text('群聊名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '成员修改的群名');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.conversation.title, '成员修改的群名');
    expect(find.text('成员修改的群名'), findsOneWidget);

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

  testWidgets('私聊详情支持确认加入黑名单和提交举报', (tester) async {
    final repository = _DetailsRepository.direct();
    await _pumpDetails(tester, repository);

    expect(find.text('黑名单'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, '黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('加入黑名单？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(repository.blocked, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, '黑名单'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '加入黑名单'));
    await tester.pumpAndSettle();
    expect(repository.blocked, isTrue);
    expect(find.text('对方无法向你发送私聊消息'), findsOneWidget);

    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();
    expect(find.text('举报 Alice'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('user-report-reason-selector')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('user-report-reason-sexualContent')));
    await tester.pumpAndSettle();
    expect(find.text('色情低俗'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('user-report-description')), '持续发送广告');
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: find.byKey(const ValueKey('user-report-description')),
                matching: find.byType(EditableText)))
            .controller
            .text,
        '持续发送广告');
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交举报'))
            .onPressed,
        isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, '提交举报'));
    await tester.pumpAndSettle();
    expect(repository.reportReason, UserReportReason.sexualContent);
    expect(repository.reportDescription, '持续发送广告');
  });

  testWidgets('黑名单状态遇到短暂错误时重试一次', (tester) async {
    final repository = _RetryBlockRepository();
    await _pumpDetails(tester, repository);

    expect(repository.blockStatusAttempts, 2);
    expect(find.text('对方可以向你发送私聊消息'), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '黑名单'))
            .onChanged,
        isNotNull);
  });

  testWidgets('黑名单接口返回 404 时不重复请求并保留其他详情', (tester) async {
    final repository = _NotFoundBlockRepository();
    await _pumpDetails(tester, repository);

    expect(repository.blockStatusAttempts, 1);
    expect(find.text('黑名单状态暂不可用'), findsOneWidget);
    expect(find.text('举报'), findsOneWidget);
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
    String? serverUrl,
    AvatarImagePicker? avatarImagePicker,
    VoidCallback? onConversationRemoved}) async {
  await tester.binding.setSurfaceSize(const Size(600, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      home: ConversationDetailsPage(
    repository: repository,
    conversationId: repository.conversation.id,
    initialConversation: repository.conversation,
    serverUrl: serverUrl,
    avatarImagePicker: avatarImagePicker ?? pickAvatarImage,
    onOpenConversation: onOpenConversation,
    onConversationRemoved: onConversationRemoved,
  )));
  await tester.pumpAndSettle();
}

class _DetailsRepository extends DemoRepository {
  _DetailsRepository._(this.conversation,
      {this.failFullResolutionBatch = false});

  factory _DetailsRepository.group(String role,
          {List<Project> projects = const [], String avatar = ''}) =>
      _DetailsRepository._(
        ChatConversation(
          id: 'group',
          title: '工程群',
          announcement: '欢迎加入工程群',
          type: 'group',
          isPublic: false,
          avatar: avatar,
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

  factory _DetailsRepository.unavailableMember() => _DetailsRepository._(
        const ChatConversation(
          id: 'group-unavailable-member',
          title: '历史项目群',
          type: 'group',
          members: [
            Contact(
                id: 'me',
                name: '当前用户',
                avatar: '/avatars/me.webp',
                role: 'owner'),
            Contact(id: 'user-disabled', name: ''),
          ],
        ),
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
  bool blocked = false;
  UserReportReason? reportReason;
  String? reportDescription;
  String? createdName;
  List<String> createdMemberIds = const [];
  List<String> addedMemberIds = const [];
  List<String> addedAppIds = const [];
  List<String> resolvedUserIds = const [];
  final List<List<String>> resolvedUserBatches = [];
  final bool failFullResolutionBatch;
  int contactRequests = 0;
  Uint8List? uploadedAvatarBytes;
  final visibilityChanges = <bool>[];
  Completer<void>? visibilityCompleter;

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
      Contact(id: 'app-helper', name: '自动化助手', type: 'app'),
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
    if (conversation.id == 'group-unavailable-member') return const [];
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
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload) async {
    uploadedAvatarBytes = upload.bytes;
    conversation =
        _copy(avatar: 'https://chat.example.com/avatars/group-updated.webp');
  }

  @override
  Future<void> setGroupVisibility(String conversationId, bool isPublic) async {
    visibilityChanges.add(isPublic);
    await visibilityCompleter?.future;
    conversation = _copy(isPublic: isPublic);
  }

  @override
  Future<UserBlockStatus> userBlockStatus(String userId) async =>
      UserBlockStatus(userId: userId, blocked: blocked);

  @override
  Future<UserBlockStatus> setUserBlocked(String userId, bool value) async {
    blocked = value;
    return UserBlockStatus(userId: userId, blocked: value);
  }

  @override
  Future<void> reportUser(String conversationId,
      {required UserReportReason reason, required String description}) async {
    reportReason = reason;
    reportDescription = description;
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
    addedMemberIds = List.of(memberIds);
    addedAppIds = List.of(appIds);
    final contactsById = {
      for (final contact in await contacts()) contact.id: contact
    };
    conversation = _copy(members: [
      ...conversation.members,
      for (final id in memberIds)
        if (!conversation.members.any((member) => member.id == id))
          contactsById[id]!,
      for (final id in appIds)
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
    String? avatar,
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
        avatar: avatar ?? conversation.avatar,
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

class _RetryBlockRepository extends _DetailsRepository {
  _RetryBlockRepository()
      : super._(
          const ChatConversation(
            id: 'direct-retry',
            title: 'Alice',
            type: 'direct',
            members: [
              Contact(id: 'me', name: '当前用户'),
              Contact(id: 'user-alice', name: 'Alice'),
            ],
          ),
        );

  var blockStatusAttempts = 0;

  @override
  Future<UserBlockStatus> userBlockStatus(String userId) async {
    blockStatusAttempts++;
    if (blockStatusAttempts == 1) {
      throw StateError('临时网络错误');
    }
    return UserBlockStatus(userId: userId, blocked: false);
  }
}

class _NotFoundBlockRepository extends _DetailsRepository {
  _NotFoundBlockRepository()
      : super._(
          const ChatConversation(
            id: 'direct-not-found',
            title: 'Alice',
            type: 'direct',
            members: [
              Contact(id: 'me', name: '当前用户'),
              Contact(id: 'user-alice', name: 'Alice'),
            ],
          ),
        );

  var blockStatusAttempts = 0;

  @override
  Future<UserBlockStatus> userBlockStatus(String userId) async {
    blockStatusAttempts++;
    throw const MagicChatRequestException(statusCode: 404, message: '黑名单接口不存在');
  }
}
