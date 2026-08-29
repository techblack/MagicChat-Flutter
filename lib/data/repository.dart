import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/message_content.dart';

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
  Future<void> renameGroupConversation(String conversationId, String name);
  Future<void> updateGroupAnnouncement(
      String conversationId, String announcement);
  Future<void> setGroupVisibility(String conversationId, bool isPublic);
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload);
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [], List<String> appIds = const []});
  Future<void> removeConversationMember(String conversationId, String memberId);
  Future<ChatConversation> createTopic(String conversationId, String messageId);
  Future<void> forwardMessage(
      String conversationId, String messageId, String targetConversationId);
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50});
  Future<void> sendMessage(String conversationId, String text);
  Future<bool> setConversationPinned(String conversationId, bool pinned);
  Future<bool> setConversationMuted(String conversationId, bool muted);
  Future<void> markConversationRead(String conversationId, int upToSeq);
  Future<List<MessageSearchResult>> searchMessages(String keyword);
  Future<void> revokeMessage(String conversationId, String messageId);
  Future<void> sendFile(String conversationId, AttachmentUpload upload);
  Future<Uri?> attachmentUrl(String fileId);
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
      {String caption = ''});
  Future<void> sendVoice(String conversationId, AttachmentUpload upload,
      {String transcript = '', int durationMs = 0});
  Future<List<MessageReaction>> setReaction(
      String conversationId, String messageId,
      {required String text, required bool reacted});
  Future<void> submitChoice(
      String conversationId, String messageId, List<String> optionIds);
  Future<ContactDirectory> contactDirectory({String keyword = ''});
  Future<List<Contact>> contacts({String keyword = ''});
  Future<List<Contact>> resolveUsers(List<String> userIds);
  Future<List<Contact>> searchUsers(String query);
  Future<void> createFriendRequest(String userId);
  Future<List<FriendRequest>> friendRequests({String direction = 'incoming'});
  Future<void> acceptFriendRequest(String requestId);
  Future<void> rejectFriendRequest(String requestId);
  Future<void> cancelFriendRequest(String requestId);
  Future<List<Project>> projects();
  Future<Project> createProject(String name, {String description = ''});
  Future<Project> updateProject(String projectId,
      {String? name, String? description});
  Future<void> deleteProject(String projectId);
  Future<List<ProjectMember>> projectMembers(String projectId);
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
  Future<ProjectTask> createTask(String projectId, String title);
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
            id: 'team', title: '团队群聊', preview: '今天的项目进展如何？', unread: 2),
      ];

  @override
  Future<ChatConversation> createGroupConversation(String name,
          {List<String> memberIds = const [],
          List<String> appIds = const []}) async =>
      ChatConversation(id: DateTime.now().toIso8601String(), title: name);

  @override
  Future<ChatConversation> createAppConversation(String appId) async =>
      ChatConversation(id: appId, title: '应用会话');

  @override
  Future<ChatConversation> createDirectConversation(String userId) async =>
      ChatConversation(id: userId, title: '私聊');

  @override
  Future<void> dismissConversation(String conversationId) async {}

  @override
  Future<void> renameGroupConversation(
      String conversationId, String name) async {}

  @override
  Future<void> updateGroupAnnouncement(
      String conversationId, String announcement) async {}

  @override
  Future<void> setGroupVisibility(String conversationId, bool isPublic) async {}

  @override
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload) async {}

  @override
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {}

  @override
  Future<void> removeConversationMember(
      String conversationId, String memberId) async {}

  @override
  Future<ChatConversation> createTopic(
          String conversationId, String messageId) async =>
      ChatConversation(id: '$conversationId:$messageId', title: '话题');

  @override
  Future<void> forwardMessage(String conversationId, String messageId,
      String targetConversationId) async {}

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      List.unmodifiable(_messages);

  @override
  Future<void> sendMessage(String conversationId, String text) async {
    _messages.add(ChatMessage(
        id: DateTime.now().toIso8601String(),
        author: '我',
        text: text,
        mine: true));
  }

  @override
  Future<bool> setConversationPinned(
          String conversationId, bool pinned) async =>
      pinned;
  @override
  Future<bool> setConversationMuted(String conversationId, bool muted) async =>
      muted;
  @override
  Future<void> markConversationRead(String conversationId, int upToSeq) async {}

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword) async =>
      const [];

  @override
  Future<void> sendFile(String conversationId, AttachmentUpload upload) async {}
  @override
  Future<Uri?> attachmentUrl(String fileId) async => null;
  @override
  Future<void> revokeMessage(String conversationId, String messageId) async {}
  @override
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
      {String caption = ''}) async {}
  @override
  Future<void> sendVoice(String conversationId, AttachmentUpload upload,
      {String transcript = '', int durationMs = 0}) async {}

  @override
  Future<List<MessageReaction>> setReaction(
          String conversationId, String messageId,
          {required String text, required bool reacted}) async =>
      const [];
  @override
  Future<void> submitChoice(
      String conversationId, String messageId, List<String> optionIds) async {}

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
  Future<List<FriendRequest>> friendRequests(
          {String direction = 'incoming'}) async =>
      const [];
  @override
  Future<void> acceptFriendRequest(String requestId) async {}
  @override
  Future<void> rejectFriendRequest(String requestId) async {}
  @override
  Future<void> cancelFriendRequest(String requestId) async {}

  @override
  Future<List<Project>> projects() async => const [
        Project(id: '1', name: 'MagicChat Flutter 重构', taskCount: 12),
        Project(id: '2', name: '产品迭代', taskCount: 5),
      ];

  @override
  Future<Project> createProject(String name, {String description = ''}) async =>
      Project(id: DateTime.now().toIso8601String(), name: name);

  @override
  Future<Project> updateProject(String projectId,
          {String? name, String? description}) async =>
      Project(
          id: projectId, name: name ?? '项目', description: description ?? '');

  @override
  Future<void> deleteProject(String projectId) async {}

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
  Future<ProjectTask> createTask(String projectId, String title) async =>
      ProjectTask(
          id: DateTime.now().toIso8601String(),
          projectId: projectId,
          title: title,
          status: 'todo');

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

/// 服务端 `/api/client/` 的最小 HTTP 实现。所有响应先按 unknown 解码，再做字段校验。
class HttpMagicChatRepository implements MagicChatRepository {
  static const requestTimeout = Duration(seconds: 30);
  HttpMagicChatRepository(
      {required String serverUrl,
      required this.sessionToken,
      http.Client? client})
      : baseUri =
            Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/'),
        _client = client ?? http.Client();
  final Uri baseUri;
  final String sessionToken;
  final http.Client _client;
  String? _currentUserId;

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
  Future<void> uploadConversationAvatar(
      String conversationId, AttachmentUpload upload) async {
    final uri = baseUri.resolve(
        'api/client/conversations/${Uri.encodeComponent(conversationId)}/avatar');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $sessionToken'
      ..headers['Accept'] = 'application/json'
      ..files.add(upload.bytes != null
          ? http.MultipartFile.fromBytes('file', upload.bytes!,
              filename: upload.name, contentType: _mediaType(upload.mimeType))
          : await http.MultipartFile.fromPath('file', upload.path,
              filename: upload.name, contentType: _mediaType(upload.mimeType)));
    final response = await _client.send(request).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('群头像上传失败（HTTP ${response.statusCode}）');
    }
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
  Future<void> removeConversationMember(
      String conversationId, String memberId) async {
    await _request('DELETE',
        '/api/client/conversations/groups/${Uri.encodeComponent(conversationId)}/members/${Uri.encodeComponent(memberId)}');
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
  Future<void> forwardMessage(String conversationId, String messageId,
      String targetConversationId) async {
    await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/forward',
        body: {
          'client_forward_id': DateTime.now().microsecondsSinceEpoch.toString(),
          'message_ids': [messageId],
          'mode': 'single',
          'target_conversation_ids': [targetConversationId],
        });
  }

  ChatConversation _conversationFromJson(Map<String, dynamic> item) =>
      ChatConversation(
          id: '${item['id'] ?? ''}',
          title: '${item['name'] ?? '未命名会话'}',
          preview: '${item['summary'] ?? ''}',
          announcement: '${item['announcement'] ?? ''}',
          isPublic: item['visibility'] == 'public' || item['is_public'] == true,
          avatar: '${item['avatar'] ?? ''}',
          unread: (item['unread_count'] as num?)?.toInt() ?? 0,
          pinned: item['pinned'] == true,
          muted: item['notification_muted'] == true,
          lastMessageSeq: (item['last_message_seq'] as num?)?.toInt() ?? 0,
          members: _membersFromJson(item['members']));

  List<Contact> _membersFromJson(Object? value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((item) => item['id'] is String && item['name'] is String)
          .map((item) => Contact(
              id: item['id'] as String,
              name: item['name'] as String,
              online: item['online'] == true,
              type: item['type'] == 'app' ? 'app' : 'user',
              role: item['role'] == 'owner' || item['role'] == 'admin'
                  ? item['role'] as String
                  : 'member'))
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
      ..headers['Authorization'] = 'Bearer $sessionToken'
      ..headers['Accept'] = 'application/json'
      ..files.add(upload.bytes != null
          ? http.MultipartFile.fromBytes('file', upload.bytes!,
              filename: upload.name, contentType: _mediaType(upload.mimeType))
          : await http.MultipartFile.fromPath('file', upload.path,
              filename: upload.name, contentType: _mediaType(upload.mimeType)));
    final response = await _client.send(request).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('头像上传失败（HTTP ${response.statusCode}）');
    }
    final text = await response.stream.bytesToString();
    final value = _data(jsonDecode(text))['user'];
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
      'Authorization': 'Bearer $sessionToken'
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    final response = await _client
        .send(http.Request(method, uri)
          ..headers.addAll(headers)
          ..body = body == null ? '' : jsonEncode(body))
        .timeout(requestTimeout);
    final text = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('请求失败（HTTP ${response.statusCode}）');
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
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
    return values
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final content = MessageContent.parse(item['body']);
          final sender = item['sender'];
          final senderName =
              sender is Map<String, dynamic> ? sender['name'] : null;
          final senderId = sender is Map<String, dynamic> ? sender['id'] : null;
          return ChatMessage(
              id: '${item['id'] ?? ''}',
              sequence: (item['seq'] as num?)?.toInt(),
              authorId: senderId is String ? senderId : null,
              author: '${senderName ?? '用户'}',
              conversationId: conversationId,
              contentType: content.type,
              rawBody: content.raw,
              text: content.text,
              mine: senderId is String && senderId == _currentUserId,
              reactions: _reactionsFromJson(item['reactions']));
        })
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  List<MessageReaction> _reactionsFromJson(Object? value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((item) => item['text'] is String)
          .map((item) => MessageReaction(
              text: item['text'] as String,
              count: (item['count'] as num?)?.toInt() ?? 0,
              reactedByMe: item['reacted_by_me'] == true))
          .where((reaction) => reaction.count > 0)
          .toList()
      : const [];

  @override
  Future<void> sendMessage(String conversationId, String text) async =>
      _request('POST',
          '/api/client/conversations/${Uri.encodeComponent(conversationId)}/messages',
          body: {
            'client_message_id':
                DateTime.now().microsecondsSinceEpoch.toString(),
            'body': {'type': 'text', 'content': text}
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
    return _data(value)['muted'] == true;
  }

  @override
  Future<void> markConversationRead(String conversationId, int upToSeq) async {
    await _request('POST',
        '/api/client/conversations/${Uri.encodeComponent(conversationId)}/read',
        body: {'up_to_seq': upToSeq});
  }

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword) async {
    final encoded = Uri(queryParameters: {'keyword': keyword}).query;
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
          final body = MessageContent.parse(message['body']);
          final sender = message['sender'];
          final name = sender is Map<String, dynamic> ? sender['name'] : null;
          final conversationId = conversation['id'];
          final conversationName = conversation['name'];
          final chat = ChatMessage(
              id: '${message['id'] ?? ''}',
              authorId: sender is Map<String, dynamic> && sender['id'] is String
                  ? sender['id'] as String
                  : null,
              author: name is String ? name : '用户',
              conversationId: conversationId is String ? conversationId : null,
              contentType: body.type,
              rawBody: body.raw,
              text: body.text);
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
  Future<void> sendFile(String conversationId, AttachmentUpload upload) async {
    await _sendMultipart(conversationId, 'files', 'file', upload, const {});
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
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
          {String caption = ''}) async =>
      _sendMultipart(conversationId, 'images', 'image', upload,
          {'caption': caption, 'caption_type': 'text'});

  @override
  Future<void> sendVoice(String conversationId, AttachmentUpload upload,
          {String transcript = '', int durationMs = 0}) async =>
      _sendMultipart(conversationId, 'voices', 'voice', upload,
          {'transcript': transcript, 'duration_ms': '$durationMs'});

  Future<void> _sendMultipart(String conversationId, String route, String field,
      AttachmentUpload upload, Map<String, String> fields) async {
    final uri = baseUri.resolve(
        'api/client/conversations/${Uri.encodeComponent(conversationId)}/messages/$route');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $sessionToken'
      ..headers['Accept'] = 'application/json'
      ..fields['client_message_id'] =
          DateTime.now().microsecondsSinceEpoch.toString()
      ..fields.addAll(fields)
      ..files.add(upload.bytes != null
          ? http.MultipartFile.fromBytes(field, upload.bytes!,
              filename: upload.name, contentType: _mediaType(upload.mimeType))
          : await http.MultipartFile.fromPath(field, upload.path,
              filename: upload.name, contentType: _mediaType(upload.mimeType)));
    final response = await _client.send(request).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('附件发送失败（HTTP ${response.statusCode}）');
    }
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
            reactedByMe: item['reacted_by_me'] == true))
        .toList();
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
          type:
              '${value['type'] ?? (apps.contains(value) ? 'app' : 'group')}'));
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
    final values = _data(await _request('POST', '/api/client/users/resolve',
        body: {'user_ids': userIds}))['users'];
    if (values is! List) throw const FormatException('用户资料响应格式不正确');
    return values
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
            type: 'user'))
        .toList();
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
  Future<List<Project>> projects() async {
    final data = _data(await _request('GET', '/api/client/projects?limit=100'));
    final result = <Project>[];
    final personal = data['personal_project'];
    final projects = data['projects'];
    for (final value in [personal, if (projects is List) ...projects]) {
      if (value is Map<String, dynamic> &&
          value['id'] is String &&
          value['name'] is String) {
        result.add(_projectFromJson(value));
      }
    }
    return result;
  }

  @override
  Future<Project> createProject(String name, {String description = ''}) async {
    final data = _data(await _request('POST', '/api/client/projects', body: {
      'name': name,
      'description': description,
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
    return members;
  }

  @override
  Future<List<ProjectTask>> tasks(String projectId) async {
    final data = _data(await _request('GET',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks?limit=100'));
    final values = data['tasks'];
    if (values is! List) throw const FormatException('任务列表响应格式不正确');
    return values
        .whereType<Map<String, dynamic>>()
        .map((item) => ProjectTask(
            id: '${item['id'] ?? ''}',
            projectId: '${item['project_id'] ?? projectId}',
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
                : null))
        .where((task) => task.id.isNotEmpty && task.title.isNotEmpty)
        .toList();
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
      activities.addAll(
          values.whereType<Map<String, dynamic>>().map(_taskActivityFromJson));
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
  Future<ProjectTask> createTask(String projectId, String title) async {
    final data = _data(await _request(
        'POST', '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks',
        body: {'title': title}));
    return _taskFromJson(data);
  }

  @override
  Future<ProjectTask> updateTaskStatus(
      String projectId, String taskId, String status) async {
    final data = _data(await _request('PATCH',
        '/api/client/projects/${Uri.encodeComponent(projectId)}/tasks/${Uri.encodeComponent(taskId)}',
        body: {'status': status}));
    return _taskFromJson(data);
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
    return _taskFromJson(data);
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
    return _taskActivityFromJson(data);
  }

  ProjectTask _taskFromJson(Map<String, dynamic> item) => ProjectTask(
      id: '${item['id'] ?? ''}',
      projectId: '${item['project_id'] ?? ''}',
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

  ProjectMember _projectMemberFromJson(Map<String, dynamic> value) {
    if (value['id'] is! String ||
        (value['role'] != 'owner' && value['role'] != 'member') ||
        value['source_group_ids'] is! List) {
      throw const FormatException('项目成员响应格式不正确');
    }
    return ProjectMember(
        id: value['id'] as String,
        name: value['name'] is String ? value['name'] as String : '',
        nickname:
            value['nickname'] is String ? value['nickname'] as String : '',
        avatar: value['avatar'] is String ? value['avatar'] as String : '',
        email: value['email'] is String ? value['email'] as String : '',
        displayNameOverride: value['display_name'] is String
            ? value['display_name'] as String
            : '',
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
