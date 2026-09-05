import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/message_content.dart';
import 'http_client.dart';
import 'session_store.dart';
import 'contact_cache_store.dart';
import 'message_cache_store.dart';

abstract interface class MagicChatRepository {
  Future<CurrentUser> currentUser();
  Future<CurrentUser> updateProfile({String? nickname, String? avatar});
  Future<CurrentUser> uploadAvatar(AttachmentUpload upload);
  Future<List<ChatConversation>> conversations();
  Future<ChatConversation> createGroupConversation(String name,
      {List<String> memberIds = const [], List<String> appIds = const []});
  Future<ChatConversation> createAppConversation(String appId);
  Future<ChatConversation> createDirectConversation(String userId);
  Future<void> dismissConversation(String conversationId);
  Future<ChatConversation> restoreConversation(String conversationId);
  Future<ChatConversation> joinGroupConversation(String conversationId);
  Future<void> renameGroupConversation(String conversationId, String name);
  Future<void> updateGroupAnnouncement(
      String conversationId, String announcement);
  Future<void> setGroupVisibility(String conversationId, bool isPublic);
  Future<void> leaveGroupConversation(String conversationId);
  Future<void> dissolveGroupConversation(String conversationId);
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload);
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [], List<String> appIds = const []});
  Future<void> removeConversationMember(String conversationId, String memberId,
      {String memberType = 'user'});
  Future<ChatConversation> createTopic(String conversationId, String messageId);
  Future<TopicPage> topics(String conversationId,
      {String? cursor, int? limit, String status = 'all'});
  Future<TopicDetail> topicDetail(String conversationId);
  Future<ChatConversation> participateTopic(String conversationId);
  Future<ChatConversation> archiveTopic(String conversationId);
  Future<ForwardMessagesResult> forwardMessages(
      String conversationId, ForwardMessagesRequest request);
  Future<void> forwardMessage(
      String conversationId, String messageId, String targetConversationId);
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50});
  Future<AttachmentPage> attachments(String conversationId,
      {String? cursor, int limit = 50});
  Future<void> sendMessage(String conversationId, String text,
      {String? replyToMessageId});
  Future<bool> setConversationPinned(String conversationId, bool pinned);
  Future<bool> setConversationMuted(String conversationId, bool muted);
  Future<ConversationReadResult> markConversationRead(
      String conversationId, int upToSeq);
  Future<List<MessageSearchResult>> searchMessages(String keyword,
      {String? conversationId, String? senderId, DateTime? from, DateTime? to});
  Future<void> revokeMessage(String conversationId, String messageId);
  Future<void> sendFile(String conversationId, AttachmentUpload upload,
      {String? replyToMessageId});
  Future<Uri?> attachmentUrl(String fileId);
  Future<Uint8List?> downloadAttachment(String fileId);
  Future<Uint8List?> downloadResource(Uri uri);
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
      {String caption = '', String? replyToMessageId});
  Future<void> sendVoice(String conversationId, AttachmentUpload upload,
      {String transcript = '', int durationMs = 0, String? replyToMessageId});
  Future<List<MessageReaction>> setReaction(
      String conversationId, String messageId,
      {required String text, required bool reacted});
  Future<List<MessageReactionUser>> listReactionUsers(
      String conversationId, String messageId,
      {required String text});
  Future<List<MessageReactionSnapshot>> listReactionSnapshots(
      String conversationId, List<String> messageIds);
  Future<void> submitChoice(
      String conversationId, String messageId, List<String> optionIds);
  Future<List<MessageChoiceSnapshot>> listChoiceSnapshots(
      String conversationId, List<String> messageIds);
  Future<ContactDirectory> contactDirectory({String keyword = ''});
  Future<List<Contact>> contacts({String keyword = ''});
  Future<List<Contact>> resolveUsers(List<String> userIds);
  Future<List<Contact>> searchUsers(String query);
  Future<void> createFriendRequest(String userId);
  Future<void> deleteFriend(String userId);
  Future<List<FriendRequest>> friendRequests({String direction = 'incoming'});
  Future<void> acceptFriendRequest(String requestId);
  Future<void> rejectFriendRequest(String requestId);
  Future<void> cancelFriendRequest(String requestId);
  Future<List<OwnedApp>> apps();
  Future<AppCredentials> createApp(String name,
      {String description = '',
      String visibility = 'creator',
      List<String> userIds = const []});
  Future<AppCredentials> getAppCredentials(String appId);
  Future<OwnedApp> updateApp(String appId,
      {String? name,
      String? description,
      String? visibility,
      List<String>? userIds});
  Future<OwnedApp> setAppEnabled(String appId, bool enabled);
  Future<AppCredentials> regenerateAppSecret(String appId);
  Future<void> deleteApp(String appId);
  Future<OwnedApp> uploadAppAvatar(String appId, AttachmentUpload upload);
  Future<List<Project>> projects();
  Future<ProjectPage> projectPage(
      {String? cursor, int limit = 100, String keyword = ''});
  Future<Project> createProject(String name,
      {String description = '', List<String> groupIds = const []});
  Future<Project> updateProject(String projectId,
      {String? name, String? description});
  Future<void> deleteProject(String projectId);
  Future<List<ProjectGroup>> projectGroups(String projectId);
  Future<void> bindProjectGroup(String projectId, String groupId);
  Future<void> unbindProjectGroup(String projectId, String groupId);
  Future<List<ProjectMember>> projectMembers(String projectId);
  Future<ProjectTaskPage> projectTaskPage(String projectId,
      {String? cursor,
      int limit = 100,
      String keyword = '',
      String label = '',
      List<String> statuses = const [],
      List<int> priorities = const []});
  Future<List<ProjectTask>> tasks(String projectId);
  Future<List<ProjectTaskActivity>> taskActivities(
      String projectId, String taskId);
  Future<List<ProjectDocument>> documents(String projectId);
  Future<ProjectDocument> createDocument(String projectId, String title,
      {String kind = 'document', String? documentType, String? parentId});
  Future<ProjectDocument> updateDocument(String documentId,
      {String? title, String? parentId});
  Future<String> updateCollaborativeDocumentTitle(
      String documentId, String title);
  Future<void> deleteDocument(String documentId);
  Future<void> moveDocument(String documentId,
      {String? parentId, int index = 0});
  Future<ProjectTask> createTask(String projectId, String title,
      {String description = '',
      String status = 'todo',
      int priority = 2,
      String? startDate,
      String? dueDate,
      List<String> labels = const [],
      String? assigneeUserId,
      Map<String, dynamic>? reminder});
  Future<ProjectTask> updateTaskStatus(
      String projectId, String taskId, String status);
  Future<ProjectTask> updateTask(
      String projectId, String taskId, ProjectTaskUpdate update);
  Future<void> deleteTask(String projectId, String taskId);
  Future<ProjectTaskActivity> addTaskComment(
      String projectId, String taskId, String content);
}

/// 开发壳数据。接入服务端时实现本接口，UI 不依赖 HTTP/WebSocket 细节。
class DemoRepository implements MagicChatRepository {
  CurrentUser _user =
      const CurrentUser(id: 'demo', name: '演示用户', email: 'demo@example.com');

  @override
  Future<CurrentUser> currentUser() async => _user;

  @override
  Future<CurrentUser> updateProfile({String? nickname, String? avatar}) async {
    _user = CurrentUser(
        id: _user.id,
        name: _user.name,
        email: _user.email,
        nickname: nickname ?? _user.nickname,
        avatar: avatar ?? _user.avatar,
        phone: _user.phone);
    return _user;
  }

  @override
  Future<CurrentUser> uploadAvatar(AttachmentUpload upload) async => _user;

  final _messages = <ChatMessage>[
    const ChatMessage(id: '1', author: '小助手', text: '你好，欢迎使用 MagicChat！'),
    const ChatMessage(
        id: '2', author: '我', text: 'Flutter 客户端正在迁移中。', mine: true),
  ];

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
            id: 'welcome',
            title: 'MagicChat 小助手',
            preview: 'Flutter 客户端正在迁移中。'),
        ChatConversation(
            id: 'team',
            title: '团队群聊',
            preview: '今天的项目进展如何？',
            unread: 2,
            type: 'group'),
      ];

  @override
  Future<ChatConversation> createGroupConversation(String name,
          {List<String> memberIds = const [],
          List<String> appIds = const []}) async =>
      ChatConversation(
          id: DateTime.now().toIso8601String(), title: name, type: 'group');

  @override
  Future<ChatConversation> createAppConversation(String appId) async =>
      ChatConversation(id: appId, title: '应用会话');

  @override
  Future<ChatConversation> createDirectConversation(String userId) async =>
      ChatConversation(id: userId, title: '私聊');

  @override
  Future<void> dismissConversation(String conversationId) async {}

  @override
  Future<ChatConversation> restoreConversation(String conversationId) async =>
      ChatConversation(id: conversationId, title: '已恢复会话');

  @override
  Future<ChatConversation> joinGroupConversation(String conversationId) async =>
      ChatConversation(id: conversationId, title: '群聊', type: 'group');

  @override
  Future<void> renameGroupConversation(
      String conversationId, String name) async {}

  @override
  Future<void> updateGroupAnnouncement(
      String conversationId, String announcement) async {}

  @override
  Future<void> setGroupVisibility(String conversationId, bool isPublic) async {}

  @override
  Future<void> leaveGroupConversation(String conversationId) async {}

  @override
  Future<void> dissolveGroupConversation(String conversationId) async {}

  @override
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload) async {}

  @override
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {}

  @override
  Future<void> removeConversationMember(String conversationId, String memberId,
      {String memberType = 'user'}) async {}

  final _demoTopics = <ChatConversation>[];

  @override
  Future<ChatConversation> createTopic(
      String conversationId, String messageId) async {
    final topicId = '$conversationId:$messageId';
    final existing = _demoTopics.where((item) => item.id == topicId);
    if (existing.isNotEmpty) return existing.first;
    final topic = ChatConversation(
        id: topicId,
        title: '话题',
        type: 'topic',
        topic: TopicMetadata(
            archived: false,
            parentConversationId: conversationId,
            parentConversationName: '演示会话',
            parentConversationType: 'group',
            participating: true,
            sourceMessageId: messageId,
            sourceMessageSeq: 1,
            sourceSender: const TopicSourceSender(
                id: 'demo', type: 'user', name: '演示用户')));
    _demoTopics.add(topic);
    return topic;
  }

  @override
  Future<TopicPage> topics(String conversationId,
      {String? cursor, int? limit, String status = 'all'}) async {
    final values = _demoTopics.where((item) {
      final metadata = item.topic;
      if (metadata == null || metadata.parentConversationId != conversationId) {
        return false;
      }
      return status == 'archived'
          ? metadata.archived
          : status == 'active'
              ? !metadata.archived
              : true;
    }).toList();
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final safeStart = start.clamp(0, values.length);
    final end = limit == null
        ? values.length
        : (safeStart + limit).clamp(0, values.length);
    return TopicPage(
        topics: values.sublist(safeStart, end),
        nextCursor: end < values.length ? '$end' : null);
  }

  @override
  Future<TopicDetail> topicDetail(String conversationId) async {
    final conversation = _demoTopics.firstWhere(
        (item) => item.id == conversationId,
        orElse: () => throw StateError('话题不存在'));
    final metadata = conversation.topic!;
    return TopicDetail(
        canArchive: !metadata.archived,
        canParticipate: !metadata.participating && !metadata.archived,
        conversation: conversation,
        parentConversation: TopicReference(
            id: metadata.parentConversationId,
            name: metadata.parentConversationName,
            type: metadata.parentConversationType),
        sourceMessage: TopicSourceMessage(
            id: metadata.sourceMessageId,
            createdAt: '2026-08-29T10:00:00Z',
            sender: metadata.sourceSender,
            sequence: metadata.sourceMessageSeq,
            summary: '演示消息',
            body: const {'type': 'text', 'content': '演示消息'}));
  }

  ChatConversation _replaceDemoTopic(
      String conversationId, TopicMetadata metadata) {
    final index = _demoTopics.indexWhere((item) => item.id == conversationId);
    if (index < 0) throw StateError('话题不存在');
    final current = _demoTopics[index];
    final updated = ChatConversation(
        id: current.id,
        title: current.title,
        preview: current.preview,
        announcement: current.announcement,
        isPublic: current.isPublic,
        avatar: current.avatar,
        unread: current.unread,
        pinned: current.pinned,
        muted: current.muted,
        lastMessageSeq: current.lastMessageSeq,
        lastReadSeq: current.lastReadSeq,
        lastChoiceSeq: current.lastChoiceSeq,
        type: current.type,
        memberCount: current.memberCount,
        members: current.members,
        canSend: current.canSend && !metadata.archived,
        topic: metadata);
    _demoTopics[index] = updated;
    return updated;
  }

  @override
  Future<ChatConversation> participateTopic(String conversationId) async {
    final detail = await topicDetail(conversationId);
    final metadata = detail.conversation.topic!;
    if (metadata.archived) throw StateError('话题已关闭，不能参与');
    return _replaceDemoTopic(
        conversationId,
        TopicMetadata(
            archived: metadata.archived,
            parentConversationId: metadata.parentConversationId,
            parentConversationName: metadata.parentConversationName,
            parentConversationType: metadata.parentConversationType,
            participating: true,
            sourceMessageId: metadata.sourceMessageId,
            sourceMessageSeq: metadata.sourceMessageSeq,
            sourceSender: metadata.sourceSender));
  }

  @override
  Future<ChatConversation> archiveTopic(String conversationId) async {
    final detail = await topicDetail(conversationId);
    final metadata = detail.conversation.topic!;
    return _replaceDemoTopic(
        conversationId,
        TopicMetadata(
            archived: true,
            parentConversationId: metadata.parentConversationId,
            parentConversationName: metadata.parentConversationName,
            parentConversationType: metadata.parentConversationType,
            participating: metadata.participating,
            sourceMessageId: metadata.sourceMessageId,
            sourceMessageSeq: metadata.sourceMessageSeq,
            sourceSender: metadata.sourceSender));
  }

  @override
  Future<ForwardMessagesResult> forwardMessages(
      String conversationId, ForwardMessagesRequest request) async {
    final conversations = await this.conversations();
    final known = conversations.map((item) => item.id).toSet();
    final results = request.targetConversationIds.map((targetId) {
      if (!known.contains(targetId)) {
        return ForwardTargetResult(
            conversationId: targetId,
            status: 'failed',
            error: const ForwardTargetError(
                code: 'conversation_not_found', message: '目标会话不存在'));
      }
      return ForwardTargetResult(
          conversationId: targetId,
          status: 'sent',
          messages: request.mode == ForwardMode.merged
              ? [
                  ChatMessage(
                      id: 'demo-forward-${DateTime.now().microsecondsSinceEpoch}',
                      conversationId: targetId,
                      author: '我',
                      text: '转发了 ${request.messageIds.length} 条消息',
                      mine: true)
                ]
              : request.messageIds
                  .map((id) => ChatMessage(
                      id: 'demo-forward-$id-${DateTime.now().microsecondsSinceEpoch}',
                      conversationId: targetId,
                      author: '我',
                      text: '转发消息 $id',
                      mine: true))
                  .toList());
    }).toList(growable: false);
    return ForwardMessagesResult(
        sentCount: results.where((item) => item.sent).length,
        failedCount: results.where((item) => !item.sent).length,
        results: results);
  }

  @override
  Future<void> forwardMessage(String conversationId, String messageId,
      String targetConversationId) async {}

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      List.unmodifiable(_messages);

  @override
  Future<AttachmentPage> attachments(String conversationId,
          {String? cursor, int limit = 50}) async =>
      const AttachmentPage(attachments: []);

  @override
  Future<void> sendMessage(String conversationId, String text,
      {String? replyToMessageId}) async {
    _messages.add(ChatMessage(
        id: DateTime.now().toIso8601String(),
        author: '我',
        text: text,
        mine: true,
        replyTo: replyToMessageId == null
            ? null
            : MessageReply(id: replyToMessageId, author: '用户', text: '引用消息')));
  }

  @override
  Future<bool> setConversationPinned(
          String conversationId, bool pinned) async =>
      pinned;
  @override
  Future<bool> setConversationMuted(String conversationId, bool muted) async =>
      muted;
  @override
  Future<ConversationReadResult> markConversationRead(
          String conversationId, int upToSeq) async =>
      ConversationReadResult(
          conversationId: conversationId, lastReadSeq: upToSeq, unreadCount: 0);

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword,
          {String? conversationId,
          String? senderId,
          DateTime? from,
          DateTime? to}) async =>
      const [];

  @override
  Future<void> sendFile(String conversationId, AttachmentUpload upload,
      {String? replyToMessageId}) async {}
  @override
  Future<Uri?> attachmentUrl(String fileId) async => null;
  @override
  Future<Uint8List?> downloadAttachment(String fileId) async => null;

  @override
  Future<Uint8List?> downloadResource(Uri uri) async => null;
  @override
  Future<void> revokeMessage(String conversationId, String messageId) async {}
  @override
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
      {String caption = '', String? replyToMessageId}) async {}
  @override
  Future<void> sendVoice(String conversationId, AttachmentUpload upload,
      {String transcript = '',
      int durationMs = 0,
      String? replyToMessageId}) async {}

  @override
  Future<List<MessageReaction>> setReaction(
          String conversationId, String messageId,
          {required String text, required bool reacted}) async =>
      const [];

  @override
  Future<List<MessageReactionUser>> listReactionUsers(
          String conversationId, String messageId,
          {required String text}) async =>
      const [];

  @override
  Future<List<MessageReactionSnapshot>> listReactionSnapshots(
          String conversationId, List<String> messageIds) async =>
      // 演示数据没有独立的快照服务；返回空结果可保留消息本身携带的状态。
      const [];

  @override
  Future<void> submitChoice(
      String conversationId, String messageId, List<String> optionIds) async {}

  @override
  Future<List<MessageChoiceSnapshot>> listChoiceSnapshots(
          String conversationId, List<String> messageIds) async =>
      // 演示数据没有独立的快照服务；返回空结果可保留消息本身携带的状态。
      const [];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: '1', name: '小助手', online: true),
        Contact(id: '2', name: '团队成员'),
      ];

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      ContactDirectory(
          contacts: await contacts(keyword: keyword), mode: 'friends');

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async =>
      (await contacts()).where((user) => userIds.contains(user.id)).toList();

  @override
  Future<List<Contact>> searchUsers(String query) async {
    final keyword = query.trim().toLowerCase();
    return (await contacts())
        .where((user) =>
            user.name.toLowerCase().contains(keyword) || user.id == keyword)
        .toList();
  }

  @override
  Future<void> createFriendRequest(String userId) async {}

  @override
  Future<void> deleteFriend(String userId) async {}

  @override
  Future<List<FriendRequest>> friendRequests(
          {String direction = 'incoming'}) async =>
      const [];
  @override
  Future<void> acceptFriendRequest(String requestId) async {}
  @override
  Future<void> rejectFriendRequest(String requestId) async {}
  @override
  Future<void> cancelFriendRequest(String requestId) async {}

  final _apps = <OwnedApp>[
    const OwnedApp(
        id: 'demo-app',
        name: '演示应用',
        description: '用于演示应用接入配置',
        createdAt: '2026-08-29T10:00:00Z',
        updatedAt: '2026-08-29T10:00:00Z'),
  ];
  final _appSecrets = <String, String>{'demo-app': 'demo-app-secret'};

  @override
  Future<List<OwnedApp>> apps() async => List.unmodifiable(_apps);

  @override
  Future<AppCredentials> createApp(String name,
      {String description = '',
      String visibility = 'creator',
      List<String> userIds = const []}) async {
    final id = DateTime.now().toIso8601String();
    final now = DateTime.now().toUtc().toIso8601String();
    final app = OwnedApp(
        id: id,
        name: name,
        description: description,
        visibility: visibility,
        userIds:
            visibility == 'restricted' ? List.unmodifiable(userIds) : const [],
        createdAt: now,
        updatedAt: now);
    _apps.add(app);
    final secret = 'demo-secret-$id';
    _appSecrets[id] = secret;
    return AppCredentials(app: app, connectionSecret: secret);
  }

  @override
  Future<AppCredentials> getAppCredentials(String appId) async {
    final index = _apps.indexWhere((item) => item.id == appId);
    if (index < 0) throw StateError('应用不存在');
    return AppCredentials(
        app: _apps[index], connectionSecret: _appSecrets[appId]!);
  }

  @override
  Future<OwnedApp> updateApp(String appId,
      {String? name,
      String? description,
      String? visibility,
      List<String>? userIds}) async {
    final index = _apps.indexWhere((item) => item.id == appId);
    if (index < 0) throw StateError('应用不存在');
    final current = _apps[index];
    final nextVisibility = visibility ?? current.visibility;
    final updated = OwnedApp(
        id: current.id,
        name: name ?? current.name,
        description: description ?? current.description,
        avatar: current.avatar,
        connectionStatus: current.connectionStatus,
        createdAt: current.createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        enabled: current.enabled,
        visibility: nextVisibility,
        userIds: nextVisibility == 'restricted'
            ? (userIds ?? current.userIds)
            : const []);
    _apps[index] = updated;
    return updated;
  }

  @override
  Future<OwnedApp> setAppEnabled(String appId, bool enabled) async {
    final index = _apps.indexWhere((item) => item.id == appId);
    if (index < 0) throw StateError('应用不存在');
    final current = _apps[index];
    final updated = OwnedApp(
        id: current.id,
        name: current.name,
        description: current.description,
        avatar: current.avatar,
        connectionStatus: enabled ? 'offline' : 'disabled',
        createdAt: current.createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        enabled: enabled,
        visibility: current.visibility,
        userIds: current.userIds);
    _apps[index] = updated;
    return updated;
  }

  @override
  Future<AppCredentials> regenerateAppSecret(String appId) async {
    final app = (await getAppCredentials(appId)).app;
    final secret = 'demo-secret-${DateTime.now().microsecondsSinceEpoch}';
    _appSecrets[appId] = secret;
    return AppCredentials(app: app, connectionSecret: secret);
  }

  @override
  Future<void> deleteApp(String appId) async {
    _apps.removeWhere((item) => item.id == appId);
    _appSecrets.remove(appId);
  }

  @override
  Future<OwnedApp> uploadAppAvatar(
      String appId, AttachmentUpload upload) async {
    final index = _apps.indexWhere((item) => item.id == appId);
    if (index < 0) throw StateError('应用不存在');
    final current = _apps[index];
    final updated = OwnedApp(
        id: current.id,
        name: current.name,
        description: current.description,
        avatar: upload.path.isEmpty ? current.avatar : upload.path,
        connectionStatus: current.connectionStatus,
        createdAt: current.createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        enabled: current.enabled,
        visibility: current.visibility,
        userIds: current.userIds);
    _apps[index] = updated;
    return updated;
  }

  @override
  Future<List<Project>> projects() async => const [
        Project(id: '1', name: 'MagicChat Flutter 重构', taskCount: 12),
        Project(id: '2', name: '产品迭代', taskCount: 5),
      ];

  @override
  Future<ProjectPage> projectPage(
          {String? cursor, int limit = 100, String keyword = ''}) async =>
      ProjectPage(projects: await projects(), nextCursor: null);

  @override
  Future<Project> createProject(String name,
          {String description = '', List<String> groupIds = const []}) async =>
      Project(
          id: DateTime.now().toIso8601String(),
          name: name,
          description: description);

  @override
  Future<Project> updateProject(String projectId,
          {String? name, String? description}) async =>
      Project(
          id: projectId, name: name ?? '项目', description: description ?? '');

  @override
  Future<void> deleteProject(String projectId) async {}

  @override
  Future<List<ProjectGroup>> projectGroups(String projectId) async => const [];

  @override
  Future<void> bindProjectGroup(String projectId, String groupId) async {}

  @override
  Future<void> unbindProjectGroup(String projectId, String groupId) async {}

  @override
  Future<List<ProjectMember>> projectMembers(String projectId) async => const [
        ProjectMember(
            id: 'demo',
            name: '演示用户',
            email: 'demo@example.com',
            displayNameOverride: '演示用户',
            role: 'owner'),
        ProjectMember(
            id: 'member-alice',
            name: 'Alice',
            email: 'alice@example.com',
            displayNameOverride: 'Alice'),
      ];

  @override
  Future<ProjectTaskPage> projectTaskPage(String projectId,
      {String? cursor,
      int limit = 100,
      String keyword = '',
      String label = '',
      List<String> statuses = const [],
      List<int> priorities = const []}) async {
    final values = await tasks(projectId);
    return ProjectTaskPage(tasks: values, nextCursor: null);
  }

  @override
  Future<List<ProjectTask>> tasks(String projectId) async => const [
        ProjectTask(
            id: 'demo-task',
            projectId: '1',
            title: '迁移消息渲染器',
            status: 'in_progress'),
      ];

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
          String projectId, String taskId) async =>
      [
        ProjectTaskActivity(
            id: 'activity-created',
            projectId: projectId,
            taskId: taskId,
            type: 'created',
            actor: const ProjectUser(id: 'demo', name: '演示用户'),
            createdAt: '2026-08-29T10:00:00Z')
      ];

  @override
  Future<List<ProjectDocument>> documents(String projectId) async => const [];

  @override
  Future<ProjectDocument> createDocument(String projectId, String title,
          {String kind = 'document',
          String? documentType,
          String? parentId}) async =>
      ProjectDocument(
          id: DateTime.now().toIso8601String(),
          projectId: projectId,
          title: title,
          kind: kind,
          parentId: parentId,
          documentType: kind == 'document' ? documentType ?? 'document' : null);

  @override
  Future<ProjectDocument> updateDocument(String documentId,
          {String? title, String? parentId}) async =>
      ProjectDocument(
          id: documentId,
          projectId: '',
          title: title ?? '文档',
          parentId: parentId);

  @override
  Future<String> updateCollaborativeDocumentTitle(
          String documentId, String title) async =>
      title;

  @override
  Future<void> deleteDocument(String documentId) async {}

  @override
  Future<void> moveDocument(String documentId,
      {String? parentId, int index = 0}) async {}

  @override
  Future<ProjectTask> createTask(String projectId, String title,
          {String description = '',
          String status = 'todo',
          int priority = 2,
          String? startDate,
          String? dueDate,
          List<String> labels = const [],
          String? assigneeUserId,
          Map<String, dynamic>? reminder}) async =>
      ProjectTask(
          id: DateTime.now().toIso8601String(),
          projectId: projectId,
          title: title,
          status: status,
          priority: priority,
          description: description,
          startDate: startDate,
          dueDate: dueDate,
          labels: labels,
          assignee:
              assigneeUserId == null ? null : ProjectUser(id: assigneeUserId),
          reminder: reminder);

  @override
  Future<ProjectTask> updateTaskStatus(
          String projectId, String taskId, String status) async =>
      ProjectTask(
          id: taskId, projectId: projectId, title: '任务', status: status);

  @override
  Future<ProjectTask> updateTask(
          String projectId, String taskId, ProjectTaskUpdate update) async =>
      ProjectTask(
          id: taskId,
          projectId: projectId,
          title: update.title,
          status: update.status,
          description: update.description,
          priority: update.priority,
          startDate: update.startDate,
          dueDate: update.dueDate,
          labels: update.labels,
          assignee: update.assigneeUserId == null
              ? null
              : ProjectUser(id: update.assigneeUserId!),
          reminder: update.reminder);

  @override
  Future<void> deleteTask(String projectId, String taskId) async {}

  @override
  Future<ProjectTaskActivity> addTaskComment(
          String projectId, String taskId, String content) async =>
      ProjectTaskActivity(
          id: DateTime.now().toIso8601String(),
          projectId: projectId,
          taskId: taskId,
          type: 'commented',
          actor: const ProjectUser(id: 'demo', name: '演示用户'),
          content: content,
          createdAt: DateTime.now().toIso8601String());
}

class MagicChatRequestException implements Exception {
  const MagicChatRequestException(
      {required this.statusCode, required this.message, this.code});

  final int statusCode;
  final String? code;
  final String message;

  bool get isUnauthorized => statusCode == 401 || code == 'unauthorized';

  @override
  String toString() => message;
}

/// 服务端 `/api/client/` 的最小 HTTP 实现。所有响应先按 unknown 解码，再做字段校验。
class HttpMagicChatRepository implements MagicChatRepository {
  static const requestTimeout = Duration(seconds: 30);
  HttpMagicChatRepository(
      {required String serverUrl,
      required this.sessionToken,
      http.Client? client,
      void Function()? onUnauthorized})
      : baseUri =
            Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/'),
        _client = client ?? createMagicChatHttpClient(),
        _onUnauthorized = onUnauthorized;
  final Uri baseUri;
  final String sessionToken;
  final http.Client _client;
  final void Function()? _onUnauthorized;
  String? _currentUserId;
  final _projectUsers = <String, ProjectUser>{};
  final _contactCacheStore = ContactCacheStore();
  bool _projectCacheLoaded = false;

  Map<String, String> get _sessionHeaders =>
      sessionToken == SessionStore.cookieSessionToken
          ? const {}
          : {'Authorization': 'Bearer $sessionToken'};

  @override
  Future<ChatConversation> createGroupConversation(String name,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {
    final data =
        _data(await _request('POST', '/api/client/conversations/groups', body: {
      'name': name,
      'member_ids': memberIds,
      'app_ids': appIds,
    }));
    final value = data['conversation'];
    if (value is! Map<String, dynamic>)
      throw const FormatException('群聊响应格式不正确');
    return _conversationFromJson(value);
  }

  @override
  Future<ChatConversation> createAppConversation(String appId) async {
    final data = _data(await _request('POST', '/api/client/conversations/apps',
        body: {'app_id': appId}));
    final value = data['conversation'];
    if (value is! Map<String, dynamic>)
      throw const FormatException('应用会话响应格式不正确');
    return _conversationFromJson(value);
  }

  @override
  Future<ChatConversation> createDirectConversation(String userId) async {
    final data = _data(await _request(
        'POST', '/api/client/conversations/direct',
        body: {'user_id': userId}));
    final value = data['conversation'];
    if (value is! Map<String, dynamic>) {
      throw const FormatException('私聊响应格式不正确');
    }
    return _conversationFromJson(value);
  }

  @override
  Future<void> dismissConversation(String conversationId) async {
    await _request('DELETE',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}');
  }

  @override
  Future<ChatConversation> restoreConversation(String conversationId) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/restore'));
    return _conversationFromEnvelope(data, '恢复对话响应格式不正确');
  }

  @override
  Future<ChatConversation> joinGroupConversation(String conversationId) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}/join'));
    return _conversationFromEnvelope(data, '加入群聊响应格式不正确');
  }

  @override
  Future<void> renameGroupConversation(
      String conversationId, String name) async {
    await _request('PATCH',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}/name',
        body: {'name': name});
  }

  @override
  Future<void> updateGroupAnnouncement(
      String conversationId, String announcement) async {
    await _request('PATCH',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}/announcement',
        body: {'announcement': announcement});
  }

  @override
  Future<void> setGroupVisibility(String conversationId, bool isPublic) async {
    await _request('POST',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}/${isPublic ? 'public' : 'private'}');
  }

  @override
  Future<void> leaveGroupConversation(String conversationId) async {
    await _request('POST',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}/leave');
  }

  @override
  Future<void> dissolveGroupConversation(String conversationId) async {
    await _request('DELETE',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}');
  }

  @override
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload) async {
    final uri = baseUri.resolve(
        'api/client/conversations/${Uri.encodeComponent(conversationId)}/avatar');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_sessionHeaders)
      ..headers['Accept'] = 'application/json'
      ..files.add(upload.bytes != null
          ? http.MultipartFile.fromBytes('file', upload.bytes!,
              filename: upload.name, contentType: _mediaType(upload.mimeType))
          : await http.MultipartFile.fromPath('file', upload.path,
              filename: upload.name, contentType: _mediaType(upload.mimeType)));
    await _sendMultipartRequest(request, fallbackMessage: '群头像上传失败');
  }

  @override
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {
    await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/members',
        body: {'member_ids': memberIds, 'app_ids': appIds});
  }

  @override
  Future<void> removeConversationMember(String conversationId, String memberId,
      {String memberType = 'user'}) async {
    final encodedConversationId = Uri.encodeComponent(conversationId);
    final encodedMemberId = Uri.encodeComponent(memberId);
    final path = memberType == 'user'
        ? '/api/client/conversations/groups/$encodedConversationId/members/$encodedMemberId'
        : '/api/client/conversations/groups/$encodedConversationId/members/${Uri.encodeComponent(memberType)}/$encodedMemberId';
    await _request('DELETE', path);
  }

  @override
  Future<ChatConversation> createTopic(
      String conversationId, String messageId) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/${Uri.encodeComponent(messageId)}/topic'));
    final value = data['conversation'];
    if (value is! Map<String, dynamic>)
      throw const FormatException('话题响应格式不正确');
    return _conversationFromJson(value);
  }

  @override
  Future<TopicPage> topics(String conversationId,
      {String? cursor, int? limit, String status = 'all'}) async {
    final query = Uri(queryParameters: {
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      if (limit != null) 'limit': '$limit',
      if (status.trim().isNotEmpty && status != 'all') 'status': status,
    }).query;
    final suffix = query.isEmpty ? '' : '?$query';
    final data = _data(await _request('GET',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/topics$suffix'));
    return TopicPage.fromJson(data);
  }

  @override
  Future<TopicDetail> topicDetail(String conversationId) async {
    final data = _data(await _request('GET',
        '/api/client/conversations/topics/${Uri.encodeComponent(conversationId)}'));
    final detail = TopicDetail.fromJson(data);
    final source = detail.sourceMessage;
    if (source.replyTo != null || source.revokedAt != null) return detail;

    final query = Uri(queryParameters: {
      'before_seq': '${source.sequence + 1}',
      'limit': '1',
    }).query;
    final sourceData = _data(await _request('GET',
        '/api/client/conversations/${Uri.encodeComponent(detail.parentConversation.id)}/messages?$query'));
    final values = sourceData['messages'];
    if (values is! List) throw const FormatException('消息列表响应格式不正确');
    TopicSourceReply? replyTo;
    for (final item in values) {
      if (item is! Map<String, dynamic> || item['id'] != source.id) continue;
      final reply = item['reply_to'];
      if (reply is Map<String, dynamic>) {
        replyTo = TopicSourceReply.fromJson(reply);
      }
      break;
    }
    if (replyTo == null) return detail;
    return TopicDetail(
      canArchive: detail.canArchive,
      canParticipate: detail.canParticipate,
      conversation: detail.conversation,
      parentConversation: detail.parentConversation,
      sourceMessage: TopicSourceMessage(
        id: source.id,
        createdAt: source.createdAt,
        sender: source.sender,
        sequence: source.sequence,
        summary: source.summary,
        body: source.body,
        revokedAt: source.revokedAt,
        replyTo: replyTo,
      ),
    );
  }

  @override
  Future<ChatConversation> participateTopic(String conversationId) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/topics/${Uri.encodeComponent(conversationId)}/participate'));
    return _conversationFromEnvelope(data, '参与话题响应格式不正确');
  }

  @override
  Future<ChatConversation> archiveTopic(String conversationId) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/topics/${Uri.encodeComponent(conversationId)}/archive'));
    return _conversationFromEnvelope(data, '关闭话题响应格式不正确');
  }

  @override
  Future<ForwardMessagesResult> forwardMessages(
      String conversationId, ForwardMessagesRequest request) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/forward',
        body: request.toJson()));
    final sentCount = _nonNegativeInteger(data['sent_count']);
    final failedCount = _nonNegativeInteger(data['failed_count']);
    final rawResults = data['results'];
    if (sentCount == null || failedCount == null || rawResults is! List) {
      throw const FormatException('转发消息响应格式不正确');
    }
    final results = rawResults.map((item) {
      if (item is! Map<String, dynamic> ||
          item['conversation_id'] is! String ||
          (item['conversation_id'] as String).isEmpty ||
          (item['status'] != 'sent' && item['status'] != 'failed')) {
        throw const FormatException('转发消息响应格式不正确');
      }
      final status = item['status'] as String;
      final rawMessages = item['messages'];
      final messages = status == 'sent'
          ? (rawMessages is List
              ? rawMessages.map((message) {
                  if (message is! Map<String, dynamic>) {
                    throw const FormatException('转发消息响应格式不正确');
                  }
                  final parsed = _messageFromJson(
                      message, item['conversation_id'] as String);
                  if (parsed.id.isEmpty) {
                    throw const FormatException('转发消息响应格式不正确');
                  }
                  return parsed;
                }).toList(growable: false)
              : throw const FormatException('转发消息响应格式不正确'))
          : const <ChatMessage>[];
      ForwardTargetError? error;
      final rawError = item['error'];
      if (status == 'failed') {
        if (rawError is! Map<String, dynamic> ||
            rawError['code'] is! String ||
            (rawError['code'] as String).isEmpty ||
            rawError['message'] is! String ||
            (rawError['message'] as String).isEmpty) {
          throw const FormatException('转发消息响应格式不正确');
        }
        error = ForwardTargetError(
            code: rawError['code'] as String,
            message: rawError['message'] as String);
      }
      return ForwardTargetResult(
          conversationId: item['conversation_id'] as String,
          status: status,
          messages: messages,
          error: error);
    }).toList(growable: false);
    return ForwardMessagesResult(
        sentCount: sentCount, failedCount: failedCount, results: results);
  }

  int? _nonNegativeInteger(Object? value) {
    if (value is! num || !value.isFinite || value < 0 || value % 1 != 0) {
      return null;
    }
    return value.toInt();
  }

  @override
  Future<void> forwardMessage(String conversationId, String messageId,
      String targetConversationId) async {
    await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/forward',
        body: {
          'client_forward_id': newForwardClientId(),
          'message_ids': [messageId],
          'mode': ForwardMode.separate.wireValue,
          'target_conversation_ids': [targetConversationId],
        });
  }

  ChatConversation _conversationFromJson(
          Map<String, dynamic> item) =>
      ChatConversation(
          id: '${item['id'] ?? ''}',
          title: '${item['name'] ?? '未命名会话'}',
          type: '${item['type'] ?? 'direct'}',
          preview: '${item['last_message_summary'] ?? item['summary'] ?? ''}',
          announcement: '${item['announcement'] ?? ''}',
          isPublic: item['visibility'] == 'public' || item['is_public'] == true,
          avatar: '${item['avatar'] ?? ''}',
          createdAt:
              item['created_at'] is String ? item['created_at'] as String : '',
          unread: (item['unread_count'] as num?)?.toInt() ?? 0,
          pinned: item['pinned'] == true,
          muted: item['notification_muted'] == true || item['muted'] == true,
          lastMessageAt: item['last_message_at'] is String
              ? item['last_message_at'] as String
              : '',
          lastMessageSeq: (item['last_message_seq'] as num?)?.toInt() ?? 0,
          lastReadSeq: (item['last_read_seq'] as num?)?.toInt() ?? 0,
          lastMentionedSeq: (item['last_mentioned_seq'] as num?)?.toInt() ?? 0,
          lastChoiceSeq: (item['last_choice_seq'] as num?)?.toInt() ?? 0,
          memberCount: (item['member_count'] as num?)?.toInt() ?? 0,
          canSend: item['can_send'] != false,
          topic: item['topic'] is Map<String, dynamic>
              ? TopicMetadata.fromJson(item['topic'] as Map<String, dynamic>)
              : null,
          members: _membersFromJson(item['members']));

  ChatConversation _conversationFromEnvelope(
      Map<String, dynamic> data, String errorMessage) {
    final value = data['conversation'];
    if (value is! Map<String, dynamic>) {
      throw FormatException(errorMessage);
    }
    return _conversationFromJson(value);
  }

  List<Contact> _membersFromJson(Object? value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((item) =>
              item['id'] is String && (item['id'] as String).trim().isNotEmpty)
          .map((item) => Contact(
              id: item['id'] as String,
              name: item['name'] is String ? item['name'] as String : '',
              online: item['online'] == true,
              type: item['type'] == 'app' ? 'app' : 'user',
              role: item['role'] == 'owner' || item['role'] == 'admin'
                  ? item['role'] as String
                  : 'member',
              nickname:
                  item['nickname'] is String ? item['nickname'] as String : '',
              email: item['email'] is String ? item['email'] as String : '',
              phone: item['phone'] is String ? item['phone'] as String : '',
              avatar: item['avatar'] is String ? item['avatar'] as String : ''))
          .toList()
      : const [];

  @override
  Future<CurrentUser> currentUser() async {
    final data = _data(await _request('GET', '/api/client/me'));
    final value = data['user'];
    if (value is! Map<String, dynamic>)
      throw const FormatException('用户信息响应格式不正确');
    final user = _userFromJson(value);
    _currentUserId = user.id;
    return user;
  }

  @override
  Future<CurrentUser> updateProfile({String? nickname, String? avatar}) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (avatar != null) body['avatar'] = avatar;
    final data = _data(await _request('PATCH', '/api/client/me', body: body));
    final value = data['user'];
    if (value is! Map<String, dynamic>)
      throw const FormatException('用户信息响应格式不正确');
    return _userFromJson(value);
  }

  @override
  Future<CurrentUser> uploadAvatar(AttachmentUpload upload) async {
    final uri = baseUri.resolve('api/client/me/avatar');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_sessionHeaders)
      ..headers['Accept'] = 'application/json'
      ..files.add(upload.bytes != null
          ? http.MultipartFile.fromBytes('file', upload.bytes!,
              filename: upload.name, contentType: _mediaType(upload.mimeType))
          : await http.MultipartFile.fromPath('file', upload.path,
              filename: upload.name, contentType: _mediaType(upload.mimeType)));
    final response =
        await _sendMultipartRequest(request, fallbackMessage: '头像上传失败');
    final value = _data(response)['user'];
    if (value is! Map<String, dynamic>)
      throw const FormatException('用户信息响应格式不正确');
    return _userFromJson(value);
  }

  CurrentUser _userFromJson(Map<String, dynamic> value) => CurrentUser(
      id: '${value['id'] ?? ''}',
      name: '${value['name'] ?? ''}',
      email: '${value['email'] ?? ''}',
      nickname: '${value['nickname'] ?? ''}',
      avatar: '${value['avatar'] ?? ''}',
      phone: '${value['phone'] ?? ''}');

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final uri = baseUri.resolve(path.replaceFirst(RegExp(r'^/'), ''));
    final headers = <String, String>{
      'Accept': 'application/json',
      ..._sessionHeaders,
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    final response = await _client
        .send(http.Request(method, uri)
          ..headers.addAll(headers)
          ..body = body == null ? '' : jsonEncode(body))
        .timeout(requestTimeout);
    final text = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _requestException(response.statusCode, text);
    }
    if (text.isEmpty) return null;
    final value = jsonDecode(text);
    if (value is Map<String, dynamic> && value['success'] == false) {
      throw _requestException(response.statusCode, text);
    }
    return value;
  }

  MagicChatRequestException _requestException(int statusCode, String body,
      {String fallbackMessage = '请求失败'}) {
    String? code;
    String? message;
    try {
      final value = jsonDecode(body);
      final error = value is Map<String, dynamic> ? value['error'] : null;
      if (error is Map<String, dynamic>) {
        if (error['code'] is String) code = error['code'] as String;
        if (error['message'] is String) message = error['message'] as String;
      }
    } catch (_) {
      // 非 JSON 错误响应回退到 HTTP 状态信息。
    }
    final exception = MagicChatRequestException(
        statusCode: statusCode,
        code: code,
        message: message?.trim().isNotEmpty == true
            ? message!.trim()
            : '$fallbackMessage（HTTP $statusCode）');
    if (exception.isUnauthorized) _onUnauthorized?.call();
    return exception;
  }

  Future<Map<String, dynamic>> _sendMultipartRequest(
      http.MultipartRequest request,
      {required String fallbackMessage}) async {
    final response = await _client.send(request).timeout(requestTimeout);
    final text = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _requestException(response.statusCode, text,
          fallbackMessage: fallbackMessage);
    }
    if (text.isEmpty) return const {};
    final value = jsonDecode(text);
    if (value is Map<String, dynamic> && value['success'] == false) {
      throw _requestException(response.statusCode, text,
          fallbackMessage: fallbackMessage);
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException('服务端响应格式不正确');
    }
    return value;
  }

  Map<String, dynamic> _data(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('服务端响应格式不正确');
    }
    final data = value['data'];
    return data is Map<String, dynamic> ? data : value;
  }

  @override
  Future<List<ChatConversation>> conversations() async {
    final data = _data(await _request('GET', '/api/client/conversations'));
    final values = data['conversations'];
    if (values is! List) throw const FormatException('会话列表响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .map(_conversationFromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50}) async {
    final query = <String, String>{'limit': '$limit'};
    if (beforeSeq != null) query['before_seq'] = '$beforeSeq';
    final suffix = Uri(queryParameters: query).query;
    final data = _data(await _request('GET',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages?$suffix'));
    final values = data['messages'];
    if (values is! List) throw const FormatException('消息列表响应格式不正确');
    final parsed = values
        .whereType<Map<String, dynamic>>()
        .map((item) => _messageFromJson(item, conversationId))
        .where((item) => item.id.isNotEmpty)
        .toList();
    final rawPage = data['page'];
    if (rawPage == null) return parsed;
    if (rawPage is! Map<String, dynamic>) {
      throw const FormatException('消息分页响应格式不正确');
    }
    int? pageInt(Object? value) => value is num && value.isFinite
        ? value.toInt() == value
            ? value.toInt()
            : null
        : null;
    final limitValue = pageInt(rawPage['limit']);
    final newestSeq = pageInt(rawPage['newest_seq']);
    final oldestSeq = pageInt(rawPage['oldest_seq']);
    if (rawPage['has_more_before'] is! bool ||
        rawPage['has_more_after'] is! bool ||
        limitValue == null ||
        newestSeq == null ||
        oldestSeq == null) {
      throw const FormatException('消息分页响应格式不正确');
    }
    return MessagePage(
        messages: parsed,
        hasMoreBefore: rawPage['has_more_before'] as bool,
        hasMoreAfter: rawPage['has_more_after'] as bool,
        limit: limitValue,
        newestSeq: newestSeq,
        oldestSeq: oldestSeq);
  }

  ChatMessage _messageFromJson(
      Map<String, dynamic> item, String conversationId) {
    final content = MessageContent.fromEnvelope(item['body'],
        revokedAt: item['revoked_at']);
    final editableBody = item['editable_body'];
    final editableText = editableBody is Map<String, dynamic>
        ? MessageContent.parse(editableBody).text
        : null;
    final sender = item['sender'];
    final senderId = sender is Map<String, dynamic> ? sender['id'] : null;
    final senderName = sender is Map<String, dynamic> ? sender['name'] : null;
    final senderNickname =
        sender is Map<String, dynamic> ? sender['nickname'] : null;
    return ChatMessage(
        id: '${item['id'] ?? ''}',
        sequence: (item['seq'] as num?)?.toInt(),
        createdAt:
            item['created_at'] is String ? item['created_at'] as String : '',
        authorId: senderId is String ? senderId : null,
        author: senderNickname is String && senderNickname.trim().isNotEmpty
            ? senderNickname.trim()
            : senderName is String && senderName.trim().isNotEmpty
                ? senderName.trim()
                : '成员',
        conversationId: conversationId,
        contentType: content.type,
        rawBody: content.raw,
        text: content.text,
        editableText: editableText,
        choice: parseMessageChoiceState(item['choice']),
        replyTo: _replyFromJson(item['reply_to']) ??
            _replyFromMessageId(item['reply_to_message_id']),
        topic: _topicFromJson(item['topic']),
        mine: senderId is String && senderId == _currentUserId,
        reactions: _reactionsFromJson(item['reactions']));
  }

  @override
  Future<AttachmentPage> attachments(String conversationId,
      {String? cursor, int limit = 50}) async {
    final normalizedCursor = cursor?.trim();
    final query = Uri(queryParameters: {
      if (normalizedCursor != null && normalizedCursor.isNotEmpty)
        'cursor': normalizedCursor,
      'limit': '$limit',
    }).query;
    final data = _data(await _request('GET',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/attachments?$query'));
    return AttachmentPage.fromJson(data);
  }

  List<MessageReaction> _reactionsFromJson(Object? value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((item) => item['text'] is String)
          .map((item) => MessageReaction(
              text: item['text'] as String,
              count: (item['count'] as num?)?.toInt() ?? 0,
              reactedByMe: item['reacted_by_me'] == true,
              users: _reactionUsersFromJson(item['users'])))
          .where((reaction) => reaction.count > 0)
          .toList()
      : const [];

  List<MessageReactionUser> _reactionUsersFromJson(Object? value) =>
      value is List
          ? value
              .whereType<Map<String, dynamic>>()
              .where((item) =>
                  item['id'] is String && (item['id'] as String).isNotEmpty)
              .map((item) => MessageReactionUser(
                  id: item['id'] as String,
                  name: item['name'] is String ? item['name'] as String : ''))
              .toList(growable: false)
          : const [];

  List<String> _snapshotMessageIds(List<String> messageIds) {
    if (messageIds.isEmpty || messageIds.length > 100) {
      throw const FormatException('消息快照请求格式不正确');
    }
    final ids = <String>[];
    final seen = <String>{};
    for (final rawId in messageIds) {
      final id = rawId.trim();
      if (id.isNotEmpty && seen.add(id)) ids.add(id);
    }
    if (ids.isEmpty) {
      throw const FormatException('消息快照请求格式不正确');
    }
    return ids;
  }

  @override
  Future<List<MessageReactionSnapshot>> listReactionSnapshots(
      String conversationId, List<String> messageIds) async {
    final ids = _snapshotMessageIds(messageIds);
    final data = _data(await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/reactions/query',
        body: {'message_ids': ids}));
    if (data['conversation_id'] != conversationId ||
        data['snapshots'] is! List) {
      throw const FormatException('消息表情快照响应格式不正确');
    }
    final rawSnapshots = data['snapshots'] as List;
    if (rawSnapshots.length != ids.length) {
      throw const FormatException('消息表情快照响应格式不正确');
    }
    final snapshots = <MessageReactionSnapshot>[];
    for (var index = 0; index < rawSnapshots.length; index++) {
      final value = rawSnapshots[index];
      if (value is! Map<String, dynamic>) {
        throw const FormatException('消息表情快照响应格式不正确');
      }
      final snapshot = MessageReactionSnapshot.fromJson(value,
          conversationId: conversationId);
      if (snapshot.messageId != ids[index]) {
        throw const FormatException('消息表情快照响应格式不正确');
      }
      snapshots.add(snapshot);
    }
    return snapshots;
  }

  @override
  Future<List<MessageChoiceSnapshot>> listChoiceSnapshots(
      String conversationId, List<String> messageIds) async {
    final ids = _snapshotMessageIds(messageIds);
    final data = _data(await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/choices/query',
        body: {'message_ids': ids}));
    if (data['conversation_id'] != conversationId ||
        data['snapshots'] is! List) {
      throw const FormatException('选择状态快照响应格式不正确');
    }
    final rawSnapshots = data['snapshots'] as List;
    if (rawSnapshots.length != ids.length) {
      throw const FormatException('选择状态快照响应格式不正确');
    }
    final snapshots = <MessageChoiceSnapshot>[];
    for (var index = 0; index < rawSnapshots.length; index++) {
      final value = rawSnapshots[index];
      if (value is! Map<String, dynamic>) {
        throw const FormatException('选择状态快照响应格式不正确');
      }
      final snapshot =
          MessageChoiceSnapshot.fromJson(value, conversationId: conversationId);
      if (snapshot.messageId != ids[index]) {
        throw const FormatException('选择状态快照响应格式不正确');
      }
      snapshots.add(snapshot);
    }
    return snapshots;
  }

  MessageReply? _replyFromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['id'] is! String) return null;
    final sender = value['sender'];
    final nickname = sender is Map<String, dynamic> ? sender['nickname'] : null;
    final name = sender is Map<String, dynamic> ? sender['name'] : null;
    final senderId = sender is Map<String, dynamic> ? sender['id'] : null;
    final author = nickname is String && nickname.trim().isNotEmpty
        ? nickname.trim()
        : name is String && name.trim().isNotEmpty
            ? name.trim()
            : '用户';
    final summary = value['summary'];
    return MessageReply(
        id: value['id'] as String,
        author: author,
        authorId: senderId is String ? senderId : null,
        text: summary is String && summary.isNotEmpty ? summary : '[消息]');
  }

  MessageReply? _replyFromMessageId(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return MessageReply(id: value.trim(), author: '成员', text: '[消息]');
  }

  MessageTopic? _topicFromJson(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('消息话题信息响应格式不正确');
    }
    return MessageTopic.fromJson(value);
  }

  @override
  Future<void> sendMessage(String conversationId, String text,
          {String? replyToMessageId}) async =>
      _request('POST',
          '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages',
          body: {
            'client_message_id':
                DateTime.now().microsecondsSinceEpoch.toString(),
            'body': {'type': 'text', 'content': text},
            if (replyToMessageId != null)
              'reply_to_message_id': replyToMessageId,
          });

  @override
  Future<bool> setConversationPinned(String conversationId, bool pinned) async {
    final value = await _request(pinned ? 'PUT' : 'DELETE',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/pin');
    return _data(value)['pinned'] == true;
  }

  @override
  Future<bool> setConversationMuted(String conversationId, bool muted) async {
    final value = await _request(muted ? 'PUT' : 'DELETE',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/mute');
    final data = _data(value);
    return data['muted'] == true || data['notification_muted'] == true;
  }

  @override
  Future<ConversationReadResult> markConversationRead(
      String conversationId, int upToSeq) async {
    final data = _data(await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/read',
        body: {'up_to_seq': upToSeq}));
    return ConversationReadResult(
        conversationId: data['conversation_id'] is String
            ? data['conversation_id'] as String
            : conversationId,
        lastReadSeq: (data['last_read_seq'] as num?)?.toInt() ?? upToSeq,
        unreadCount: (data['unread_count'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword,
      {String? conversationId,
      String? senderId,
      DateTime? from,
      DateTime? to}) async {
    final normalizedConversationId = conversationId?.trim();
    final normalizedSenderId = senderId?.trim();
    final encoded = Uri(queryParameters: {
      'keyword': keyword.trim(),
      if (normalizedConversationId != null &&
          normalizedConversationId.isNotEmpty)
        'conversation_id': normalizedConversationId,
      if (normalizedSenderId != null && normalizedSenderId.isNotEmpty)
        'sender_id': normalizedSenderId,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    }).query;
    final data =
        _data(await _request('GET', '/api/client/search/messages?$encoded'));
    final values = data['items'];
    if (values is! List) throw const FormatException('搜索响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final conversation = item['conversation'];
          final message = item['message'];
          if (conversation is! Map<String, dynamic> ||
              message is! Map<String, dynamic>) {
            return null;
          }
          final body = MessageContent.fromEnvelope(message['body'],
              revokedAt: message['revoked_at']);
          final editableBody = message['editable_body'];
          final editableText = editableBody is Map<String, dynamic>
              ? MessageContent.parse(editableBody).text
              : null;
          final sender = message['sender'];
          final senderName = message['sender_name'];
          final name = sender is Map<String, dynamic> ? sender['name'] : null;
          final nickname =
              sender is Map<String, dynamic> ? sender['nickname'] : null;
          final conversationId = conversation['id'];
          final conversationName = conversation['name'];
          final chat = ChatMessage(
              id: '${message['id'] ?? ''}',
              sequence: (message['seq'] as num?)?.toInt(),
              createdAt: message['created_at'] is String
                  ? message['created_at'] as String
                  : '',
              authorId: sender is Map<String, dynamic> && sender['id'] is String
                  ? sender['id'] as String
                  : null,
              author: nickname is String && nickname.trim().isNotEmpty
                  ? nickname.trim()
                  : senderName is String && senderName.trim().isNotEmpty
                      ? senderName.trim()
                      : name is String && name.trim().isNotEmpty
                          ? name.trim()
                          : '成员',
              conversationId: conversationId is String ? conversationId : null,
              contentType: body.type,
              rawBody: body.raw,
              text: body.text,
              editableText: editableText,
              replyTo: _replyFromJson(message['reply_to']) ??
                  _replyFromMessageId(message['reply_to_message_id']));
          return conversationId is String && conversationName is String
              ? MessageSearchResult(
                  conversationId: conversationId,
                  conversationName: conversationName,
                  message: chat)
              : null;
        })
        .whereType<MessageSearchResult>()
        .toList();
  }

  @override
  Future<void> revokeMessage(String conversationId, String messageId) async {
    await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/${Uri.encodeComponent(messageId)}/revoke');
  }

  @override
  Future<void> sendFile(String conversationId, AttachmentUpload upload,
      {String? replyToMessageId}) async {
    await _sendMultipart(conversationId, 'files', 'file', upload, const {},
        replyToMessageId: replyToMessageId);
  }

  @override
  Future<Uri?> attachmentUrl(String fileId) async {
    final data = _data(
        await _request('POST', '/api/client/temporary-files/read-urls', body: {
      'file_ids': [fileId]
    }));
    final urls = data['urls'];
    if (urls is! List || urls.isEmpty) return null;
    final value = urls.first;
    final url = value is Map<String, dynamic> ? value['url'] : null;
    return url is String && Uri.tryParse(url) != null ? Uri.parse(url) : null;
  }

  @override
  Future<Uint8List?> downloadAttachment(String fileId) async {
    final uri = await attachmentUrl(fileId);
    if (uri == null) return null;
    final response = await _client.get(uri).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('附件下载失败（HTTP ${response.statusCode}）');
    }
    return response.bodyBytes;
  }

  @override
  Future<Uint8List?> downloadResource(Uri uri) async {
    final sameOrigin = uri.scheme == baseUri.scheme &&
        uri.host == baseUri.host &&
        uri.port == baseUri.port;
    final response = await _client
        .get(uri, headers: sameOrigin ? _sessionHeaders : const {})
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('资源下载失败（HTTP ${response.statusCode}）');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
          {String caption = '', String? replyToMessageId}) async =>
      _sendMultipart(conversationId, 'images', 'image', upload,
          {'caption': caption, 'caption_type': 'text'},
          replyToMessageId: replyToMessageId);

  @override
  Future<void> sendVoice(String conversationId, AttachmentUpload upload,
          {String transcript = '',
          int durationMs = 0,
          String? replyToMessageId}) async =>
      _sendMultipart(conversationId, 'voices', 'voice', upload,
          {'transcript': transcript, 'duration_ms': '$durationMs'},
          replyToMessageId: replyToMessageId);

  Future<void> _sendMultipart(String conversationId, String route, String field,
      AttachmentUpload upload, Map<String, String> fields,
      {String? replyToMessageId}) async {
    final uri = baseUri.resolve(
        'api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/$route');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_sessionHeaders)
      ..headers['Accept'] = 'application/json'
      ..fields['client_message_id'] =
          DateTime.now().microsecondsSinceEpoch.toString()
      ..fields.addAll(fields);
    if (replyToMessageId != null) {
      request.fields['reply_to_message_id'] = replyToMessageId;
    }
    request.files.add(upload.bytes != null
        ? http.MultipartFile.fromBytes(field, upload.bytes!,
            filename: upload.name, contentType: _mediaType(upload.mimeType))
        : await http.MultipartFile.fromPath(field, upload.path,
            filename: upload.name, contentType: _mediaType(upload.mimeType)));
    await _sendMultipartRequest(request, fallbackMessage: '附件发送失败');
  }

  http.MediaType _mediaType(String value) {
    final parts = value.split('/');
    return parts.length == 2
        ? http.MediaType(parts[0], parts[1])
        : http.MediaType('application', 'octet-stream');
  }

  @override
  Future<List<MessageReaction>> setReaction(
      String conversationId, String messageId,
      {required String text, required bool reacted}) async {
    final data = _data(await _request('PUT',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/${Uri.encodeComponent(messageId)}/reactions',
        body: {'text': text, 'reacted': reacted}));
    final values = data['reactions'];
    if (values is! List) throw const FormatException('表情响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .map((item) => MessageReaction(
            text: '${item['text'] ?? ''}',
            count: (item['count'] as num?)?.toInt() ?? 0,
            reactedByMe: item['reacted_by_me'] == true,
            users: _reactionUsersFromJson(item['users'])))
        .toList();
  }

  @override
  Future<List<MessageReactionUser>> listReactionUsers(
      String conversationId, String messageId,
      {required String text}) async {
    final query = Uri(queryParameters: {'text': text}).query;
    final data = _data(await _request('GET',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/${Uri.encodeComponent(messageId)}/reactions/users?$query'));
    if (data['conversation_id'] != conversationId ||
        data['message_id'] != messageId ||
        data['text'] != text ||
        data['users'] is! List) {
      throw const FormatException('表情参与者响应格式不正确');
    }
    final users = (data['users'] as List).map((value) {
      if (value is! Map<String, dynamic> ||
          value['id'] is! String ||
          (value['id'] as String).isEmpty) {
        throw const FormatException('表情参与者响应格式不正确');
      }
      return MessageReactionUser(
          id: value['id'] as String,
          name: value['name'] is String ? value['name'] as String : '');
    }).toList(growable: false);
    return users;
  }

  @override
  Future<void> submitChoice(String conversationId, String messageId,
          List<String> optionIds) async =>
      _request('PUT',
          '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/${Uri.encodeComponent(messageId)}/choice-response',
          body: {'option_ids': optionIds.toSet().toList()});

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async {
    final query = keyword.trim().isEmpty
        ? ''
        : '?${Uri(queryParameters: {'keyword': keyword.trim()}).query}';
    final data = _data(await _request('GET', '/api/client/contacts$query'));
    final result = <Contact>[];
    final apps = data['apps'];
    final groups = data['groups'];
    if (apps is! List || groups is! List) {
      throw const FormatException('通讯录响应格式不正确');
    }
    for (final value in [...apps, ...groups]) {
      if (value is! Map<String, dynamic> ||
          value['id'] is! String ||
          value['name'] is! String) {
        continue;
      }
      result.add(Contact(
          id: value['id'] as String,
          name: value['name'] as String,
          online: value['online'] == true,
          avatar: '${value['avatar'] ?? ''}',
          type: '${value['type'] ?? (apps.contains(value) ? 'app' : 'group')}',
          joined: value['joined'] == true,
          memberCount: (value['member_count'] as num?)?.toInt() ?? 0,
          visibility: value['visibility'] == 'public' ? 'public' : 'private'));
    }
    final userIds = data['user_ids'];
    if (userIds is List) {
      final ids =
          userIds.whereType<String>().where((id) => id.isNotEmpty).toList();
      result.addAll(await resolveUsers(ids.take(100).toList()));
    }
    final mode = data['directory_mode'];
    if (mode != 'organization' && mode != 'friends') {
      throw const FormatException('通讯录响应格式不正确');
    }
    return ContactDirectory(contacts: result, mode: mode as String);
  }

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async =>
      (await contactDirectory(keyword: keyword)).contacts;

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async {
    if (userIds.isEmpty) return const [];
    final result = <Contact>[];
    for (var start = 0; start < userIds.length; start += 100) {
      final end = (start + 100).clamp(0, userIds.length);
      final values = _data(await _request('POST', '/api/client/users/resolve',
          body: {'user_ids': userIds.sublist(start, end)}))['users'];
      if (values is! List) throw const FormatException('用户资料响应格式不正确');
      result.addAll(values
          .whereType<Map<String, dynamic>>()
          .where((item) => item['id'] is String && item['name'] is String)
          .map((item) => Contact(
              id: item['id'] as String,
              name: item['name'] as String,
              online: item['online'] == true,
              nickname: '${item['nickname'] ?? ''}',
              email: '${item['email'] ?? ''}',
              phone: '${item['phone'] ?? ''}',
              avatar: '${item['avatar'] ?? ''}',
              type: 'user')));
    }
    return result;
  }

  @override
  Future<List<Contact>> searchUsers(String query) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final ids = _data(await _request('POST', '/api/client/users/search',
        body: {'query': value}))['user_ids'];
    if (ids is! List || ids.any((id) => id is! String)) {
      throw const FormatException('用户查找响应格式不正确');
    }
    return resolveUsers(ids.cast<String>());
  }

  @override
  Future<void> createFriendRequest(String userId) async {
    await _request('POST', '/api/client/friend-requests',
        body: {'user_id': userId});
  }

  @override
  Future<void> deleteFriend(String userId) async {
    await _request(
        'DELETE', '/api/client/friends/${Uri.encodeComponent(userId)}');
  }

  @override
  Future<List<FriendRequest>> friendRequests(
      {String direction = 'incoming'}) async {
    final query = Uri(queryParameters: {'direction': direction}).query;
    final values =
        _data(await _request('GET', '/api/client/friend-requests?$query'))[
            'requests'];
    if (values is! List) throw const FormatException('好友申请响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .where((item) => item['id'] is String)
        .map((item) => FriendRequest(
            id: item['id'] as String,
            userId: direction == 'incoming'
                ? '${item['requester_user_id'] ?? ''}'
                : '${item['addressee_user_id'] ?? ''}',
            status: '${item['status'] ?? ''}'))
        .where((item) => item.userId.isNotEmpty)
        .toList();
  }

  @override
  Future<void> acceptFriendRequest(String requestId) async => _request('POST',
      '/api/client/friend-requests/${Uri.encodeComponent(requestId)}/accept');

  @override
  Future<void> rejectFriendRequest(String requestId) async => _request('POST',
      '/api/client/friend-requests/${Uri.encodeComponent(requestId)}/reject');

  @override
  Future<void> cancelFriendRequest(String requestId) async => _request('DELETE',
      '/api/client/friend-requests/${Uri.encodeComponent(requestId)}');

  @override
  Future<List<OwnedApp>> apps() async {
    final data = _data(await _request('GET', '/api/client/apps'));
    final values = data['apps'];
    if (values is! List) throw const FormatException('应用列表响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .map(OwnedApp.fromJson)
        .toList();
  }

  @override
  Future<AppCredentials> createApp(String name,
      {String description = '',
      String visibility = 'creator',
      List<String> userIds = const []}) async {
    final data = _data(await _request('POST', '/api/client/apps', body: {
      'name': name,
      'description': description,
      'visibility': visibility,
      'user_ids': visibility == 'restricted' ? userIds : [],
    }));
    return _appCredentialsFromJson(data);
  }

  @override
  Future<AppCredentials> getAppCredentials(String appId) async {
    final data = _data(await _request(
        'GET', '/api/client/apps/${Uri.encodeComponent(appId)}'));
    return _appCredentialsFromJson(data);
  }

  @override
  Future<OwnedApp> updateApp(String appId,
      {String? name,
      String? description,
      String? visibility,
      List<String>? userIds}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (visibility != null) body['visibility'] = visibility;
    if (userIds != null) {
      body['user_ids'] =
          visibility == null || visibility == 'restricted' ? userIds : [];
    }
    final data = _data(await _request(
        'PATCH', '/api/client/apps/${Uri.encodeComponent(appId)}',
        body: body));
    return _ownedAppFromEnvelope(data);
  }

  @override
  Future<OwnedApp> setAppEnabled(String appId, bool enabled) async {
    final data = _data(await _request(
        'POST',
        '/api/client/apps/${Uri.encodeComponent(appId)}/'
            '${enabled ? 'enable' : 'disable'}'));
    return _ownedAppFromEnvelope(data);
  }

  @override
  Future<AppCredentials> regenerateAppSecret(String appId) async {
    final data = _data(await _request('POST',
        '/api/client/apps/${Uri.encodeComponent(appId)}/secret/regenerate'));
    return _appCredentialsFromJson(data);
  }

  @override
  Future<void> deleteApp(String appId) async {
    await _request('DELETE', '/api/client/apps/${Uri.encodeComponent(appId)}');
  }

  @override
  Future<OwnedApp> uploadAppAvatar(
      String appId, AttachmentUpload upload) async {
    final uri =
        baseUri.resolve('api/client/apps/${Uri.encodeComponent(appId)}/avatar');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_sessionHeaders)
      ..headers['Accept'] = 'application/json'
      ..files.add(upload.bytes != null
          ? http.MultipartFile.fromBytes('file', upload.bytes!,
              filename: upload.name, contentType: _mediaType(upload.mimeType))
          : await http.MultipartFile.fromPath('file', upload.path,
              filename: upload.name, contentType: _mediaType(upload.mimeType)));
    final response =
        await _sendMultipartRequest(request, fallbackMessage: '上传应用头像失败');
    if (response.isEmpty) throw const FormatException('应用响应格式不正确');
    return _ownedAppFromEnvelope(_data(response));
  }

  OwnedApp _ownedAppFromEnvelope(Map<String, dynamic> data) {
    final value = data['app'];
    if (value is! Map<String, dynamic>) {
      throw const FormatException('应用响应格式不正确');
    }
    return OwnedApp.fromJson(value);
  }

  AppCredentials _appCredentialsFromJson(Map<String, dynamic> data) {
    return AppCredentials.fromJson(data);
  }

  @override
  Future<List<Project>> projects() async {
    final result = <Project>[];
    String? cursor;
    do {
      final page = await projectPage(cursor: cursor);
      if (cursor == null && page.personalProject != null) {
        result.add(page.personalProject!);
      }
      result.addAll(page.projects);
      final next = page.nextCursor;
      if (next == null || next.isEmpty || next == cursor) break;
      cursor = next;
    } while (true);
    return result;
  }

  @override
  Future<ProjectPage> projectPage(
      {String? cursor, int limit = 100, String keyword = ''}) async {
    final query = Uri(queryParameters: {
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    }).query;
    final data = _data(await _request('GET', '/api/client/projects?$query'));
    final personal = data['personal_project'];
    final values = data['projects'];
    if (personal != null && personal is! Map<String, dynamic>) {
      throw const FormatException('个人项目响应格式不正确');
    }
    if (values is! List) throw const FormatException('项目列表响应格式不正确');
    final projects =
        values.whereType<Map<String, dynamic>>().map(_projectFromJson).toList();
    return ProjectPage(
        personalProject: personal is Map<String, dynamic>
            ? _projectFromJson(personal)
            : null,
        projects: projects,
        nextCursor: data['next_cursor'] as String?);
  }

  @override
  Future<Project> createProject(String name,
      {String description = '', List<String> groupIds = const []}) async {
    final data = _data(await _request('POST', '/api/client/projects', body: {
      'name': name,
      'description': description,
      'group_ids': groupIds,
    }));
    return _projectFromJson(data);
  }

  @override
  Future<Project> updateProject(String projectId,
      {String? name, String? description}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    final data = _data(await _request(
        'PATCH', '/api/client/projects/${Uri.encodeComponent(projectId)}',
        body: body));
    return _projectFromJson(data);
  }

  @override
  Future<void> deleteProject(String projectId) async {
    await _request(
        'DELETE', '/api/client/projects/${Uri.encodeComponent(projectId)}');
  }

  @override
  Future<List<ProjectGroup>> projectGroups(String projectId) async {
    final groups = <ProjectGroup>[];
    String? cursor;
    do {
      final query = Uri(queryParameters: {
        'limit': '100',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      }).query;
      final data = _data(await _request('GET',
          '/api/client/projects/${Uri.encodeComponent(projectId)}/groups?$query'));
      final values = data['groups'];
      if (values is! List) throw const FormatException('项目群组响应格式不正确');
      groups.addAll(
          values.whereType<Map<String, dynamic>>().map(_projectGroupFromJson));
      final next = data['next_cursor'] as String?;
      if (next == null || next.isEmpty || next == cursor) break;
      cursor = next;
    } while (true);
    return groups;
  }

  @override
  Future<void> bindProjectGroup(String projectId, String groupId) async {
    await _request('PUT',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/groups/${Uri.encodeComponent(groupId)}');
  }

  @override
  Future<void> unbindProjectGroup(String projectId, String groupId) async {
    await _request('DELETE',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/groups/${Uri.encodeComponent(groupId)}');
  }

  @override
  Future<List<ProjectMember>> projectMembers(String projectId) async {
    final members = <ProjectMember>[];
    String? cursor;
    do {
      final query = Uri(queryParameters: {
        'limit': '100',
        if (cursor != null) 'cursor': cursor,
      }).query;
      final data = _data(await _request('GET',
          '/api/client/projects/${Uri.encodeComponent(projectId)}/members?$query'));
      final values = data['members'];
      if (values is! List) {
        throw const FormatException('项目成员响应格式不正确');
      }
      members.addAll(
          values.whereType<Map<String, dynamic>>().map(_projectMemberFromJson));
      cursor = data['next_cursor'] as String?;
    } while (cursor != null && cursor.isNotEmpty);
    final incomplete = members
        .where(_needsProjectUserProfile)
        .map((member) => member.id)
        .toSet()
        .toList();
    if (incomplete.isEmpty) return members;
    final users = await resolveUsers(incomplete);
    final usersById = {for (final user in users) user.id: user};
    return members.map((member) {
      final user = usersById[member.id];
      if (user == null) return member;
      return ProjectMember(
          id: member.id,
          name: user.name.isEmpty ? member.name : user.name,
          nickname: user.nickname.isEmpty ? member.nickname : user.nickname,
          avatar: user.avatar.isEmpty ? member.avatar : user.avatar,
          email: user.email.isEmpty ? member.email : user.email,
          displayNameOverride: user.displayName,
          role: member.role,
          status: member.status,
          sourceGroupIds: member.sourceGroupIds);
    }).toList();
  }

  @override
  Future<List<ProjectTask>> tasks(String projectId) async {
    return (await projectTaskPage(projectId)).tasks;
  }

  @override
  Future<ProjectTaskPage> projectTaskPage(String projectId,
      {String? cursor,
      int limit = 100,
      String keyword = '',
      String label = '',
      List<String> statuses = const [],
      List<int> priorities = const []}) async {
    final normalizedStatuses = statuses
        .map((status) => status.trim())
        .where((status) => status.isNotEmpty)
        .join(',');
    final normalizedPriorities =
        priorities.map((priority) => '$priority').join(',');
    final query = Uri(queryParameters: {
      'limit': '$limit',
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      if (label.trim().isNotEmpty) 'label': label.trim(),
      if (normalizedStatuses.isNotEmpty) 'status': normalizedStatuses,
      if (normalizedPriorities.isNotEmpty) 'priority': normalizedPriorities,
    }).query;
    final data = _data(await _request('GET',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks?$query'));
    final values = data['tasks'];
    if (values is! List) throw const FormatException('任务列表响应格式不正确');
    final parsed = values
        .whereType<Map<String, dynamic>>()
        .map((item) => _taskFromJson(item, defaultProjectId: projectId))
        .where((task) => task.id.isNotEmpty && task.title.isNotEmpty)
        .toList();
    final nextCursor = data['next_cursor'];
    if (nextCursor != null && nextCursor is! String) {
      throw const FormatException('任务游标响应格式不正确');
    }
    final normalizedCursor = (nextCursor as String?)?.trim();
    return ProjectTaskPage(
        tasks: await _hydrateProjectTasks(parsed),
        nextCursor: normalizedCursor == null || normalizedCursor.isEmpty
            ? null
            : normalizedCursor);
  }

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
      String projectId, String taskId) async {
    final activities = <ProjectTaskActivity>[];
    String? cursor;
    do {
      final query = Uri(queryParameters: {
        'limit': '100',
        if (cursor != null) 'cursor': cursor,
      }).query;
      final data = _data(await _request('GET',
          '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks/${Uri.encodeComponent(taskId)}/activities?$query'));
      final values = data['activities'];
      if (values is! List) {
        throw const FormatException('任务动态响应格式不正确');
      }
      final page = values
          .whereType<Map<String, dynamic>>()
          .map(_taskActivityFromJson)
          .toList();
      activities.addAll(await _hydrateProjectActivities(page));
      cursor = data['next_cursor'] as String?;
    } while (cursor != null && cursor.isNotEmpty);
    return activities;
  }

  @override
  Future<List<ProjectDocument>> documents(String projectId) async {
    final data = _data(await _request('GET',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/documents'));
    final values = data['documents'];
    if (values is! List) throw const FormatException('文档列表响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .map((item) => ProjectDocument(
              id: '${item['id'] ?? ''}',
              projectId: '${item['project_id'] ?? projectId}',
              title: '${item['title'] ?? ''}',
              kind: '${item['kind'] ?? 'document'}',
              parentId: item['parent_id'] as String?,
              documentType: item['document_type'] as String?,
              sortOrder: (item['sort_order'] as num?)?.toInt() ?? 0,
              schemaVersion: (item['schema_version'] as num?)?.toInt() ?? 1,
            ))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  @override
  Future<ProjectDocument> createDocument(String projectId, String title,
      {String kind = 'document',
      String? documentType,
      String? parentId}) async {
    final data = _data(await _request('POST',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/documents',
        body: {
          'kind': kind,
          'title': title,
          'parent_id': parentId,
          if (kind == 'document') 'document_type': documentType ?? 'document',
        }));
    return _documentFromJson(data);
  }

  @override
  Future<ProjectDocument> updateDocument(String documentId,
      {String? title, String? parentId}) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (parentId != null) body['parent_id'] = parentId;
    final data = _data(await _request(
        'PATCH', '/api/client/documents/${Uri.encodeComponent(documentId)}',
        body: body));
    return _documentFromJson(data);
  }

  @override
  Future<String> updateCollaborativeDocumentTitle(
      String documentId, String title) async {
    final data = _data(await _request('PATCH',
        '/api/client/document/collaboration/${Uri.encodeComponent(documentId)}/title',
        body: {'title': title}));
    if (data['document_id'] != documentId || data['title'] is! String) {
      throw const FormatException('文档标题响应格式不正确');
    }
    return data['title'] as String;
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    await _request(
        'DELETE', '/api/client/documents/${Uri.encodeComponent(documentId)}');
  }

  @override
  Future<void> moveDocument(String documentId,
      {String? parentId, int index = 0}) async {
    await _request(
        'POST', '/api/client/documents/${Uri.encodeComponent(documentId)}/move',
        body: {
          'parent_id': parentId,
          'index': index,
        });
  }

  @override
  Future<ProjectTask> createTask(String projectId, String title,
      {String description = '',
      String status = 'todo',
      int priority = 2,
      String? startDate,
      String? dueDate,
      List<String> labels = const [],
      String? assigneeUserId,
      Map<String, dynamic>? reminder}) async {
    final data = _data(await _request(
        'POST', '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks',
        body: {
          'title': title,
          'description': description,
          'status': status,
          'priority': priority,
          'start_date': startDate,
          'due_date': dueDate,
          'labels': labels,
          'assignee_user_id': assigneeUserId,
          'reminder': reminder,
        }));
    return _hydrateProjectTask(_taskFromJson(data));
  }

  @override
  Future<ProjectTask> updateTaskStatus(
      String projectId, String taskId, String status) async {
    final data = _data(await _request('PATCH',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks/${Uri.encodeComponent(taskId)}',
        body: {'status': status}));
    return _hydrateProjectTask(_taskFromJson(data));
  }

  @override
  Future<ProjectTask> updateTask(
      String projectId, String taskId, ProjectTaskUpdate update) async {
    final body = <String, dynamic>{
      'title': update.title,
      'description': update.description,
      'status': update.status,
      'priority': update.priority,
      'start_date': update.startDate,
      'due_date': update.dueDate,
      'labels': update.labels,
      'assignee_user_id': update.assigneeUserId,
      'reminder': update.reminder,
    };
    final data = _data(await _request('PATCH',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks/${Uri.encodeComponent(taskId)}',
        body: body));
    return _hydrateProjectTask(_taskFromJson(data));
  }

  @override
  Future<void> deleteTask(String projectId, String taskId) async {
    await _request('DELETE',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks/${Uri.encodeComponent(taskId)}');
  }

  @override
  Future<ProjectTaskActivity> addTaskComment(
      String projectId, String taskId, String content) async {
    final data = _data(await _request('POST',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks/${Uri.encodeComponent(taskId)}/comments',
        body: {'content': content}));
    return _hydrateProjectActivity(_taskActivityFromJson(data));
  }

  ProjectTask _taskFromJson(Map<String, dynamic> item,
          {String? defaultProjectId}) =>
      ProjectTask(
          id: '${item['id'] ?? ''}',
          projectId: '${item['project_id'] ?? defaultProjectId ?? ''}',
          title: '${item['title'] ?? ''}',
          status: '${item['status'] ?? 'todo'}',
          description: '${item['description'] ?? ''}',
          priority: (item['priority'] as num?)?.toInt() ?? 2,
          startDate: item['start_date'] as String?,
          dueDate: item['due_date'] as String?,
          labels: _labels(item['labels']),
          assignee: item['assignee'] is Map<String, dynamic>
              ? _projectUserFromJson(item['assignee'] as Map<String, dynamic>)
              : null,
          reminder: item['reminder'] is Map<String, dynamic>
              ? item['reminder'] as Map<String, dynamic>
              : null);

  List<String> _labels(Object? value) => value is List
      ? value
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList()
      : const [];

  Project _projectFromJson(Map<String, dynamic> value) {
    if (value['id'] is! String || value['name'] is! String) {
      throw const FormatException('项目响应格式不正确');
    }
    final taskCounts = value['task_counts'];
    return Project(
        id: value['id'] as String,
        name: value['name'] as String,
        description: value['description'] is String
            ? value['description'] as String
            : '',
        avatar: value['avatar'] is String ? value['avatar'] as String : '',
        isPersonal: value['is_personal'] == true,
        updatedAt:
            value['updated_at'] is String ? value['updated_at'] as String : '',
        taskCount:
            taskCounts is Map<String, dynamic> && taskCounts['total'] is num
                ? (taskCounts['total'] as num).toInt()
                : null);
  }

  ProjectGroup _projectGroupFromJson(Map<String, dynamic> value) {
    if (value['id'] is! String || value['name'] is! String) {
      throw const FormatException('项目群组响应格式不正确');
    }
    return ProjectGroup(
        id: value['id'] as String,
        name: value['name'] as String,
        avatar: value['avatar'] is String ? value['avatar'] as String : '',
        status: value['status'] is String ? value['status'] as String : '',
        memberCount: (value['member_count'] as num?)?.toInt() ?? 0,
        createdAt:
            value['created_at'] is String ? value['created_at'] as String : '');
  }

  ProjectDocument _documentFromJson(Map<String, dynamic> value) {
    if (value['id'] is! String ||
        value['project_id'] is! String ||
        value['title'] is! String) {
      throw const FormatException('文档响应格式不正确');
    }
    return ProjectDocument(
        id: value['id'] as String,
        projectId: value['project_id'] as String,
        title: value['title'] as String,
        kind: value['kind'] is String ? value['kind'] as String : 'document',
        parentId: value['parent_id'] as String?,
        documentType: value['document_type'] as String?,
        sortOrder: (value['sort_order'] as num?)?.toInt() ?? 0,
        schemaVersion: (value['schema_version'] as num?)?.toInt() ?? 1);
  }

  ProjectUser _projectUserFromJson(Map<String, dynamic> value) {
    if (value['id'] is! String) {
      throw const FormatException('项目用户响应格式不正确');
    }
    return ProjectUser(
        id: value['id'] as String,
        name: value['name'] is String ? value['name'] as String : '',
        nickname:
            value['nickname'] is String ? value['nickname'] as String : '',
        avatar: value['avatar'] is String ? value['avatar'] as String : '');
  }

  Future<List<ProjectTask>> _hydrateProjectTasks(
      List<ProjectTask> tasks) async {
    final users = <ProjectUser>[];
    for (final task in tasks) {
      if (task.assignee case final assignee?
          when _needsProjectUserProfile(assignee)) {
        users.add(assignee);
      }
    }
    await _resolveProjectUsers(users);
    return tasks.map(_mergeProjectTaskUsers).toList(growable: false);
  }

  Future<ProjectTask> _hydrateProjectTask(ProjectTask task) async {
    await _resolveProjectUsers([
      if (task.assignee case final assignee?
          when _needsProjectUserProfile(assignee))
        assignee
    ]);
    return _mergeProjectTaskUsers(task);
  }

  Future<List<ProjectTaskActivity>> _hydrateProjectActivities(
      List<ProjectTaskActivity> activities) async {
    await _resolveProjectUsers([
      for (final activity in activities)
        if (_needsProjectUserProfile(activity.actor)) activity.actor
    ]);
    return activities.map(_mergeProjectActivityUser).toList(growable: false);
  }

  Future<ProjectTaskActivity> _hydrateProjectActivity(
      ProjectTaskActivity activity) async {
    if (_needsProjectUserProfile(activity.actor)) {
      await _resolveProjectUsers([activity.actor]);
    }
    return _mergeProjectActivityUser(activity);
  }

  bool _needsProjectUserProfile(ProjectUser user) =>
      user.nickname.trim().isEmpty &&
      (user.name.trim().isEmpty || user.name.trim() == user.id);

  Future<void> _resolveProjectUsers(Iterable<ProjectUser> users) async {
    await _loadProjectUserCache();
    final missing = users
        .where((user) => user.id.trim().isNotEmpty)
        .where((user) => !_projectUsers.containsKey(user.id))
        .map((user) => user.id)
        .toSet()
        .toList(growable: false);
    if (missing.isEmpty) return;
    try {
      final resolved = await resolveUsers(missing);
      for (final user in resolved) {
        _projectUsers[user.id] = ProjectUser(
            id: user.id,
            name: user.name,
            nickname: user.nickname,
            avatar: user.avatar);
      }
      if (resolved.isNotEmpty) {
        await _contactCacheStore.write(_projectCacheScope, resolved);
      }
    } catch (_) {
      // 用户资料补全失败时保留接口返回值，项目任务仍可正常使用。
    }
  }

  MessageCacheScope? get _projectCacheScope {
    final userId = _currentUserId?.trim();
    if (userId == null || userId.isEmpty) return null;
    return MessageCacheScope(
        serverUrl: baseUri.toString().replaceFirst(RegExp(r'/+$'), ''),
        userId: userId);
  }

  Future<void> _loadProjectUserCache() async {
    if (_projectCacheLoaded) return;
    final scope = _projectCacheScope;
    if (scope == null) return;
    final cached = await _contactCacheStore.read(scope);
    for (final user in cached.where((contact) => contact.type == 'user')) {
      _projectUsers[user.id] = ProjectUser(
          id: user.id,
          name: user.name,
          nickname: user.nickname,
          avatar: user.avatar);
    }
    _projectCacheLoaded = true;
  }

  ProjectTask _mergeProjectTaskUsers(ProjectTask task) => ProjectTask(
      id: task.id,
      projectId: task.projectId,
      title: task.title,
      status: task.status,
      priority: task.priority,
      description: task.description,
      startDate: task.startDate,
      dueDate: task.dueDate,
      labels: task.labels,
      assignee:
          task.assignee == null ? null : _mergeProjectUser(task.assignee!),
      reminder: task.reminder);

  ProjectTaskActivity _mergeProjectActivityUser(ProjectTaskActivity activity) =>
      ProjectTaskActivity(
          id: activity.id,
          projectId: activity.projectId,
          taskId: activity.taskId,
          type: activity.type,
          actor: _mergeProjectUser(activity.actor),
          content: activity.content,
          changes: activity.changes,
          createdAt: activity.createdAt);

  ProjectUser _mergeProjectUser(ProjectUser user) {
    final resolved = _projectUsers[user.id];
    if (resolved == null) return user;
    return ProjectUser(
        id: user.id,
        name: resolved.name.trim().isEmpty ? user.name : resolved.name,
        nickname: resolved.nickname.trim().isEmpty
            ? user.nickname
            : resolved.nickname,
        avatar: resolved.avatar.trim().isEmpty ? user.avatar : resolved.avatar);
  }

  ProjectMember _projectMemberFromJson(Map<String, dynamic> value) {
    if (value['id'] is! String ||
        (value['role'] != 'owner' && value['role'] != 'member') ||
        value['source_group_ids'] is! List) {
      throw const FormatException('项目成员响应格式不正确');
    }
    final id = value['id'] as String;
    final name =
        value['name'] is String && (value['name'] as String).trim().isNotEmpty
            ? value['name'] as String
            : id;
    return ProjectMember(
        id: id,
        name: name,
        nickname:
            value['nickname'] is String ? value['nickname'] as String : '',
        avatar: value['avatar'] is String ? value['avatar'] as String : '',
        email: value['email'] is String ? value['email'] as String : '',
        displayNameOverride: value['display_name'] is String
            ? value['display_name'] as String
            : name,
        role: value['role'] as String,
        status: value['status'] is String ? value['status'] as String : '',
        sourceGroupIds:
            (value['source_group_ids'] as List).whereType<String>().toList());
  }

  ProjectTaskActivity _taskActivityFromJson(Map<String, dynamic> value) {
    final actor = value['actor'];
    final changes = value['changes'];
    if (value['id'] is! String ||
        value['project_id'] is! String ||
        value['task_id'] is! String ||
        !const ['created', 'updated', 'commented'].contains(value['type']) ||
        actor is! Map<String, dynamic> ||
        value['content'] is! String ||
        changes is! List ||
        value['created_at'] is! String) {
      throw const FormatException('任务动态响应格式不正确');
    }
    return ProjectTaskActivity(
        id: value['id'] as String,
        projectId: value['project_id'] as String,
        taskId: value['task_id'] as String,
        type: value['type'] as String,
        actor: _projectUserFromJson(actor),
        content: value['content'] as String,
        changes: changes
            .whereType<Map<String, dynamic>>()
            .where((change) => change['field'] is String)
            .map((change) => ProjectTaskActivityChange(
                field: change['field'] as String,
                from: change['from'],
                to: change['to']))
            .toList(),
        createdAt: value['created_at'] as String);
  }
}
