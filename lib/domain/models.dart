import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

class ChatConversation {
  const ChatConversation(
      {required this.id,
      required this.title,
      this.preview = '',
      this.announcement = '',
      this.isPublic = false,
      this.avatar = '',
      this.createdAt = '',
      this.unread = 0,
      this.pinned = false,
      this.muted = false,
      this.lastMessageAt = '',
      this.lastMessageSeq = 0,
      this.lastReadSeq = 0,
      this.lastMentionedSeq = 0,
      this.lastChoiceSeq = 0,
      this.type = 'direct',
      this.memberCount = 0,
      this.members = const [],
      this.canSend = true,
      this.topic});
  final String id;
  final String title;
  final String preview;
  final String announcement;
  final bool isPublic;
  final String avatar;
  final String createdAt;
  final int unread;
  final bool pinned;
  final bool muted;
  final String lastMessageAt;
  final int lastMessageSeq;
  final int lastReadSeq;
  final int lastMentionedSeq;
  final int lastChoiceSeq;
  final String type;
  final int memberCount;
  final List<Contact> members;
  final bool canSend;
  final TopicMetadata? topic;

  int get effectiveMemberCount => max(memberCount, members.length);

  String get displayTitle {
    final value = title.trim();
    if (value.isNotEmpty && value != id) return value;
    for (final member in members) {
      final name = member.displayName.trim();
      if (name.isNotEmpty && name != '成员') return name;
    }
    return switch (type) {
      'app' => '应用会话',
      'group' => '群聊',
      'topic' => '话题',
      _ => '私聊',
    };
  }

  factory ChatConversation.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('会话响应格式不正确');
    }
    final rawTopic = value['topic'];
    if (rawTopic != null && rawTopic is! Map<String, dynamic>) {
      throw const FormatException('会话话题信息响应格式不正确');
    }
    final rawMembers = value['members'];
    final members = rawMembers is List
        ? rawMembers
            .whereType<Map<String, dynamic>>()
            .where((item) =>
                item['id'] is String &&
                (item['id'] as String).trim().isNotEmpty)
            .map((item) => Contact(
                id: item['id'] as String,
                name: item['name'] is String ? item['name'] as String : '',
                avatar:
                    item['avatar'] is String ? item['avatar'] as String : '',
                nickname: item['nickname'] is String
                    ? item['nickname'] as String
                    : '',
                email: item['email'] is String ? item['email'] as String : '',
                phone: item['phone'] is String ? item['phone'] as String : '',
                role:
                    item['role'] is String ? item['role'] as String : 'member',
                type: item['type'] == 'app' ? 'app' : 'user'))
            .toList(growable: false)
        : const <Contact>[];
    return ChatConversation(
      id: id,
      title: name,
      type: value['type'] is String ? value['type'] as String : 'direct',
      preview: value['last_message_summary'] is String
          ? value['last_message_summary'] as String
          : value['summary'] is String
              ? value['summary'] as String
              : '',
      announcement: value['announcement'] is String
          ? value['announcement'] as String
          : '',
      isPublic: value['visibility'] == 'public' || value['is_public'] == true,
      avatar: value['avatar'] is String ? value['avatar'] as String : '',
      createdAt:
          value['created_at'] is String ? value['created_at'] as String : '',
      unread: (value['unread_count'] as num?)?.toInt() ?? 0,
      pinned: value['pinned'] == true,
      muted: value['notification_muted'] == true || value['muted'] == true,
      lastMessageAt: value['last_message_at'] is String
          ? value['last_message_at'] as String
          : '',
      lastMessageSeq: (value['last_message_seq'] as num?)?.toInt() ?? 0,
      lastReadSeq: (value['last_read_seq'] as num?)?.toInt() ?? 0,
      lastMentionedSeq: (value['last_mentioned_seq'] as num?)?.toInt() ?? 0,
      lastChoiceSeq: (value['last_choice_seq'] as num?)?.toInt() ?? 0,
      memberCount: (value['member_count'] as num?)?.toInt() ?? 0,
      canSend: value['can_send'] != false,
      members: members,
      topic: rawTopic is Map<String, dynamic>
          ? TopicMetadata.fromJson(rawTopic)
          : null,
    );
  }
}

class ConversationReadResult {
  const ConversationReadResult({
    required this.conversationId,
    required this.lastReadSeq,
    required this.unreadCount,
  });

  final String conversationId;
  final int lastReadSeq;
  final int unreadCount;
}

class TopicSourceSender {
  const TopicSourceSender(
      {required this.id, required this.type, this.name = '', this.avatar = ''});

  final String id;
  final String name;
  final String avatar;
  final String type;

  factory TopicSourceSender.fromJson(Map<String, dynamic> value,
      {bool allowSystem = false}) {
    final rawId = value['id'];
    final type = value['type'];
    final validType =
        type == 'user' || type == 'app' || (allowSystem && type == 'system');
    final id = rawId == null && type == 'system' && allowSystem ? '' : rawId;
    if (id is! String || (id.isEmpty && type != 'system') || !validType) {
      throw const FormatException('话题来源消息发送者响应格式不正确');
    }
    return TopicSourceSender(
        id: id,
        type: type as String,
        name: value['name'] is String ? value['name'] as String : '',
        avatar: value['avatar'] is String ? value['avatar'] as String : '');
  }

  Map<String, dynamic> toJson() => {
        'avatar': avatar,
        'id': id,
        'name': name,
        'type': type,
      };
}

class TopicMetadata {
  const TopicMetadata(
      {required this.archived,
      required this.parentConversationId,
      required this.parentConversationName,
      required this.parentConversationType,
      required this.participating,
      required this.sourceMessageId,
      required this.sourceMessageSeq,
      required this.sourceSender});

  final bool archived;
  final String parentConversationId;
  final String parentConversationName;
  final String parentConversationType;
  final bool participating;
  final String sourceMessageId;
  final int sourceMessageSeq;
  final TopicSourceSender sourceSender;

  factory TopicMetadata.fromJson(Map<String, dynamic> value) {
    final parentId = value['parent_conversation_id'];
    final parentName = value['parent_conversation_name'];
    final sourceId = value['source_message_id'];
    final sourceSeq = value['source_message_seq'];
    final sender = value['source_sender'];
    if (parentId is! String ||
        parentId.isEmpty ||
        parentName is! String ||
        parentName.isEmpty ||
        sourceId is! String ||
        sourceId.isEmpty ||
        sourceSeq is! num ||
        !sourceSeq.isFinite ||
        sourceSeq % 1 != 0 ||
        sender is! Map<String, dynamic>) {
      throw const FormatException('会话话题信息响应格式不正确');
    }
    return TopicMetadata(
      archived: value['archived'] == true,
      parentConversationId: parentId,
      parentConversationName: parentName,
      parentConversationType:
          _topicParentType(value['parent_conversation_type']),
      participating: value['participating'] == true,
      sourceMessageId: sourceId,
      sourceMessageSeq: sourceSeq.toInt(),
      sourceSender: TopicSourceSender.fromJson(sender),
    );
  }

  Map<String, dynamic> toJson() => {
        'archived': archived,
        'parent_conversation_id': parentConversationId,
        'parent_conversation_name': parentConversationName,
        'parent_conversation_type': parentConversationType,
        'participating': participating,
        'source_message_id': sourceMessageId,
        'source_message_seq': sourceMessageSeq,
        'source_sender': sourceSender.toJson(),
      };
}

class TopicReference {
  const TopicReference(
      {required this.id, required this.name, this.type = 'group'});

  final String id;
  final String name;
  final String type;

  factory TopicReference.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('话题父会话响应格式不正确');
    }
    return TopicReference(
        id: id, name: name, type: _topicParentType(value['type']));
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type};
}

class TopicSourceReply {
  const TopicSourceReply(
      {required this.id,
      required this.sender,
      required this.sequence,
      required this.summary});

  final String id;
  final TopicSourceSender sender;
  final int sequence;
  final String summary;

  int get seq => sequence;

  factory TopicSourceReply.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final sequence = value['seq'];
    final summary = value['summary'];
    final sender = value['sender'];
    if (id is! String ||
        id.isEmpty ||
        sequence is! num ||
        !sequence.isFinite ||
        sequence % 1 != 0 ||
        summary is! String ||
        sender is! Map<String, dynamic>) {
      throw const FormatException('话题来源回复响应格式不正确');
    }
    return TopicSourceReply(
        id: id,
        sender: TopicSourceSender.fromJson(sender, allowSystem: true),
        sequence: sequence.toInt(),
        summary: summary);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender.toJson(),
        'seq': sequence,
        'summary': summary,
      };
}

class TopicSourceMessage {
  const TopicSourceMessage(
      {required this.id,
      required this.createdAt,
      required this.sender,
      required this.sequence,
      required this.summary,
      this.body = const {},
      this.revokedAt,
      this.replyTo});

  final String id;
  final String createdAt;
  final TopicSourceSender sender;
  final int sequence;
  final String summary;
  final Map<String, dynamic> body;
  final String? revokedAt;
  final TopicSourceReply? replyTo;

  int get seq => sequence;

  factory TopicSourceMessage.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final createdAt = value['created_at'];
    final sequence = value['seq'];
    final summary = value['summary'];
    final sender = value['sender'];
    final revokedAt = value['revoked_at'];
    final body = value['body'];
    final replyTo = value['reply_to'];
    if (id is! String ||
        id.isEmpty ||
        createdAt is! String ||
        createdAt.isEmpty ||
        sequence is! num ||
        !sequence.isFinite ||
        sequence % 1 != 0 ||
        summary is! String ||
        sender is! Map<String, dynamic> ||
        (revokedAt != null && revokedAt is! String) ||
        (replyTo != null && replyTo is! Map<String, dynamic>) ||
        (revokedAt == null && body is! Map<String, dynamic>)) {
      throw const FormatException('话题来源消息响应格式不正确');
    }
    return TopicSourceMessage(
      id: id,
      createdAt: createdAt,
      sender: TopicSourceSender.fromJson(sender),
      sequence: sequence.toInt(),
      summary: summary,
      body: revokedAt is String
          ? const {'type': 'revoked'}
          : Map<String, dynamic>.from(body as Map),
      revokedAt: revokedAt as String?,
      replyTo: replyTo is Map<String, dynamic>
          ? TopicSourceReply.fromJson(replyTo)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'body': body,
        'created_at': createdAt,
        'id': id,
        'revoked_at': revokedAt,
        'sender': sender.toJson(),
        'seq': sequence,
        'summary': summary,
        if (replyTo != null) 'reply_to': replyTo!.toJson(),
      };
}

class TopicDetail {
  const TopicDetail(
      {required this.canArchive,
      required this.canParticipate,
      required this.conversation,
      required this.parentConversation,
      required this.sourceMessage});

  final bool canArchive;
  final bool canParticipate;
  final ChatConversation conversation;
  final TopicReference parentConversation;
  final TopicSourceMessage sourceMessage;

  factory TopicDetail.fromJson(Map<String, dynamic> value) {
    final conversation = value['conversation'];
    final parent = value['parent_conversation'];
    final source = value['source_message'];
    if (conversation is! Map<String, dynamic> ||
        parent is! Map<String, dynamic> ||
        source is! Map<String, dynamic>) {
      throw const FormatException('话题详情响应格式不正确');
    }
    return TopicDetail(
      canArchive: value['can_archive'] == true,
      canParticipate: value['can_participate'] == true,
      conversation: ChatConversation.fromJson(conversation),
      parentConversation: TopicReference.fromJson(parent),
      sourceMessage: TopicSourceMessage.fromJson(source),
    );
  }

  Map<String, dynamic> toJson() => {
        'can_archive': canArchive,
        'can_participate': canParticipate,
        'conversation': {
          'id': conversation.id,
          'name': conversation.title,
          'type': conversation.type,
          'avatar': conversation.avatar,
          'can_send': conversation.canSend,
          if (conversation.topic != null) 'topic': conversation.topic!.toJson(),
        },
        'parent_conversation': parentConversation.toJson(),
        'source_message': sourceMessage.toJson(),
      };
}

class TopicPage {
  const TopicPage({required this.topics, this.nextCursor});

  final List<ChatConversation> topics;
  final String? nextCursor;

  factory TopicPage.fromJson(Map<String, dynamic> value) {
    final rawTopics = value['topics'];
    final nextCursor = value['next_cursor'];
    if (rawTopics is! List ||
        rawTopics.any((item) => item is! Map<String, dynamic>) ||
        (nextCursor != null && nextCursor is! String)) {
      throw const FormatException('话题列表响应格式不正确');
    }
    final topics = rawTopics
        .cast<Map<String, dynamic>>()
        .map(ChatConversation.fromJson)
        .toList(growable: false);
    if (topics.any((topic) => topic.type != 'topic')) {
      throw const FormatException('话题列表响应格式不正确');
    }
    final cursor = (nextCursor as String?)?.trim();
    return TopicPage(
        topics: topics,
        nextCursor: cursor == null || cursor.isEmpty ? null : cursor);
  }

  Map<String, dynamic> toJson() => {
        'next_cursor': nextCursor,
        'topics': topics
            .map((topic) => {
                  'id': topic.id,
                  'name': topic.title,
                  'type': topic.type,
                  if (topic.topic != null) 'topic': topic.topic!.toJson(),
                })
            .toList(),
      };
}

String _topicParentType(Object? value) =>
    value == 'direct' || value == 'app' ? value as String : 'group';

class ChatMessage {
  const ChatMessage(
      {required this.id,
      this.clientMessageId,
      required this.text,
      required this.author,
      this.authorId,
      this.conversationId,
      this.sequence,
      this.createdAt = '',
      this.contentType = 'text',
      this.rawBody = const {},
      this.mine = false,
      this.reactions = const [],
      this.choice,
      this.replyTo,
      this.topic,
      this.editableText});
  final String id;
  final String? clientMessageId;
  final String? conversationId;
  final int? sequence;
  final String createdAt;
  final String contentType;
  final Map<String, dynamic> rawBody;
  final String text;
  final String author;
  final String? authorId;
  final bool mine;
  final List<MessageReaction> reactions;
  final MessageChoiceState? choice;
  final MessageReply? replyTo;
  final MessageTopic? topic;
  final String? editableText;
}

/// A message list that preserves the server's history-window metadata while
/// remaining usable by existing callers expecting a `List<ChatMessage>`.
class MessagePage extends ListBase<ChatMessage> {
  MessagePage({
    required List<ChatMessage> messages,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
    required this.limit,
    required this.newestSeq,
    required this.oldestSeq,
  }) : _messages = List<ChatMessage>.of(messages);

  final List<ChatMessage> _messages;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final int limit;
  final int newestSeq;
  final int oldestSeq;

  @override
  int get length => _messages.length;

  @override
  set length(int value) => _messages.length = value;

  @override
  ChatMessage operator [](int index) => _messages[index];

  @override
  void operator []=(int index, ChatMessage value) => _messages[index] = value;
}

class MessageChoiceOption {
  const MessageChoiceOption({required this.id, required this.responseCount});

  final String id;
  final int responseCount;
}

class MessageChoiceState {
  const MessageChoiceState(
      {required this.myOptionIds,
      required this.options,
      required this.responseCount});

  final List<String> myOptionIds;
  final List<MessageChoiceOption> options;
  final int responseCount;

  bool selected(String optionId) => myOptionIds.contains(optionId);
}

/// 当前用户视角下的一条 choice 消息快照。
///
/// `status` 与服务端批量查询接口保持一致：`active`、`deleted` 或
/// `revoked`。已删除/撤回消息不会返回 choice 状态。
class MessageChoiceSnapshot {
  const MessageChoiceSnapshot({
    required this.conversationId,
    required this.messageId,
    required this.status,
    this.choice,
  });

  final String conversationId;
  final String messageId;
  final String status;
  final MessageChoiceState? choice;

  factory MessageChoiceSnapshot.fromJson(
    Map<String, dynamic> value, {
    required String conversationId,
  }) {
    final messageId = value['message_id'];
    final status = value['status'];
    final responseConversationId = value['conversation_id'];
    if ((responseConversationId != null &&
            responseConversationId != conversationId) ||
        messageId is! String ||
        messageId.isEmpty ||
        status is! String ||
        (status != 'active' && status != 'deleted' && status != 'revoked')) {
      throw const FormatException('选择状态快照响应格式不正确');
    }
    final rawChoice = value['choice'];
    final choice =
        status == 'active' ? parseMessageChoiceState(rawChoice) : null;
    if (status == 'active' && choice == null) {
      throw const FormatException('选择状态快照响应格式不正确');
    }
    return MessageChoiceSnapshot(
        conversationId: conversationId,
        messageId: messageId,
        status: status,
        choice: choice);
  }

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'message_id': messageId,
        'status': status,
        if (choice != null)
          'choice': {
            'my_option_ids': choice!.myOptionIds,
            'response_count': choice!.responseCount,
            'options': choice!.options
                .map((option) => {
                      'id': option.id,
                      'response_count': option.responseCount,
                    })
                .toList(),
          },
      };
}

MessageChoiceState? parseMessageChoiceState(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final rawMyOptionIds = value['my_option_ids'];
  // 旧服务端会把尚未作答的选项列表编码为 null，和 Web/Desktop 一样按空
  // 列表兼容；缺失字段仍视为无效响应。
  final myOptionIds =
      rawMyOptionIds == null && value.containsKey('my_option_ids')
          ? const <Object?>[]
          : rawMyOptionIds;
  final options = value['options'];
  final responseCount = value['response_count'];
  if (myOptionIds is! List ||
      options is! List ||
      responseCount is! num ||
      !responseCount.isFinite ||
      responseCount < 0 ||
      responseCount % 1 != 0) return null;
  if (!myOptionIds.every((id) => id is String && id.isNotEmpty)) return null;
  final ids = myOptionIds.cast<String>().toList(growable: false);
  final parsedOptions = <MessageChoiceOption>[];
  for (final option in options) {
    if (option is! Map<String, dynamic> ||
        option['id'] is! String ||
        (option['id'] as String).isEmpty ||
        option['response_count'] is! num ||
        !(option['response_count'] as num).isFinite ||
        (option['response_count'] as num) < 0 ||
        (option['response_count'] as num) % 1 != 0) return null;
    parsedOptions.add(MessageChoiceOption(
        id: option['id'] as String,
        responseCount: (option['response_count'] as num).toInt()));
  }
  return MessageChoiceState(
      myOptionIds: ids,
      options: parsedOptions,
      responseCount: responseCount.toInt());
}

enum ForwardMode { separate, merged }

extension ForwardModeValue on ForwardMode {
  String get wireValue => name;
}

/// 服务端用 UUID 作为转发请求的幂等键。
String newForwardClientId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

String newMessageClientId() => newForwardClientId();

class ForwardMessagesRequest {
  const ForwardMessagesRequest({
    required this.clientForwardId,
    required this.messageIds,
    required this.mode,
    required this.targetConversationIds,
  });

  final String clientForwardId;
  final List<String> messageIds;
  final ForwardMode mode;
  final List<String> targetConversationIds;

  Map<String, dynamic> toJson() => {
        'client_forward_id': clientForwardId,
        'message_ids': messageIds,
        'mode': mode.wireValue,
        'target_conversation_ids': targetConversationIds,
      };
}

class ForwardTargetError {
  const ForwardTargetError({required this.code, required this.message});

  final String code;
  final String message;
}

class ForwardTargetResult {
  const ForwardTargetResult({
    required this.conversationId,
    required this.status,
    this.messages = const [],
    this.error,
  });

  final String conversationId;
  final String status;
  final List<ChatMessage> messages;
  final ForwardTargetError? error;

  bool get sent => status == 'sent';
}

class ForwardMessagesResult {
  const ForwardMessagesResult({
    required this.sentCount,
    required this.failedCount,
    required this.results,
  });

  final int sentCount;
  final int failedCount;
  final List<ForwardTargetResult> results;
}

class MessageReply {
  const MessageReply(
      {required this.id,
      required this.author,
      required this.text,
      this.authorId,
      this.sequence});

  final String id;
  final String author;
  final String text;
  final String? authorId;
  final int? sequence;
}

/// 消息对应的话题摘要，附加在父会话中的来源消息上。
class MessageTopic {
  const MessageTopic(
      {required this.archived,
      required this.conversationId,
      this.recentReplies = const []});

  final bool archived;
  final String conversationId;
  final List<MessageTopicReply> recentReplies;

  factory MessageTopic.fromJson(Map<String, dynamic> value) {
    final conversationId = value['conversation_id'];
    final rawReplies = value['recent_replies'];
    if (conversationId is! String ||
        conversationId.isEmpty ||
        (rawReplies != null && rawReplies is! List)) {
      throw const FormatException('消息话题信息响应格式不正确');
    }
    if (rawReplies is List &&
        rawReplies.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('话题回复摘要响应格式不正确');
    }
    final replies = rawReplies is List
        ? rawReplies
            .cast<Map<String, dynamic>>()
            .map(MessageTopicReply.fromJson)
            .toList(growable: false)
        : const <MessageTopicReply>[];
    return MessageTopic(
        archived: value['archived'] == true,
        conversationId: conversationId,
        recentReplies: replies);
  }

  Map<String, dynamic> toJson() => {
        'archived': archived,
        'conversation_id': conversationId,
        'recent_replies': recentReplies.map((reply) => reply.toJson()).toList(),
      };
}

class MessageTopicReply {
  const MessageTopicReply(
      {required this.createdAt,
      required this.id,
      required this.sender,
      required this.summary});

  final String createdAt;
  final String id;
  final TopicSourceSender sender;
  final String summary;

  factory MessageTopicReply.fromJson(Map<String, dynamic> value) {
    final createdAt = value['created_at'];
    final id = value['id'];
    final summary = value['summary'];
    final sender = value['sender'];
    if (createdAt is! String ||
        createdAt.isEmpty ||
        id is! String ||
        id.isEmpty ||
        summary is! String ||
        sender is! Map<String, dynamic>) {
      throw const FormatException('话题回复摘要响应格式不正确');
    }
    return MessageTopicReply(
        createdAt: createdAt,
        id: id,
        sender: TopicSourceSender.fromJson(sender),
        summary: summary);
  }

  Map<String, dynamic> toJson() => {
        'created_at': createdAt,
        'id': id,
        'sender': sender.toJson(),
        'summary': summary,
      };
}

class MessageSearchResult {
  const MessageSearchResult(
      {required this.conversationId,
      required this.conversationName,
      required this.message});
  final String conversationId;
  final String conversationName;
  final ChatMessage message;

  String get displayConversationName {
    final value = conversationName.trim();
    return value.isNotEmpty && value != conversationId ? value : '会话';
  }
}

class AttachmentUpload {
  const AttachmentUpload(
      {required this.path,
      required this.name,
      required this.mimeType,
      this.bytes});
  final String path;
  final String name;
  final String mimeType;
  final Uint8List? bytes;
}

class ConversationAttachment {
  const ConversationAttachment({
    required this.createdAt,
    required this.fileId,
    required this.messageId,
    required this.name,
    required this.sequence,
    required this.sizeBytes,
  });

  final String createdAt;
  final String fileId;
  final String messageId;
  final String name;
  final int sequence;
  final int sizeBytes;

  int get seq => sequence;

  factory ConversationAttachment.fromJson(Map<String, dynamic> value) {
    final createdAt = value['created_at'];
    final fileId = value['file_id'];
    final messageId = value['message_id'];
    final name = value['name'];
    final sequence = value['seq'];
    final sizeBytes = value['size_bytes'];
    if (createdAt is! String ||
        createdAt.isEmpty ||
        fileId is! String ||
        fileId.isEmpty ||
        messageId is! String ||
        messageId.isEmpty ||
        name is! String ||
        name.isEmpty ||
        sequence is! num ||
        !sequence.isFinite ||
        sequence % 1 != 0 ||
        sequence < 1 ||
        sizeBytes is! num ||
        !sizeBytes.isFinite ||
        sizeBytes % 1 != 0 ||
        sizeBytes < 0) {
      throw const FormatException('附件响应格式不正确');
    }
    return ConversationAttachment(
      createdAt: createdAt,
      fileId: fileId,
      messageId: messageId,
      name: name,
      sequence: sequence.toInt(),
      sizeBytes: sizeBytes.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'created_at': createdAt,
        'file_id': fileId,
        'message_id': messageId,
        'name': name,
        'seq': sequence,
        'size_bytes': sizeBytes,
      };
}

class AttachmentPage {
  const AttachmentPage({required this.attachments, this.nextCursor});

  final List<ConversationAttachment> attachments;
  final String? nextCursor;

  factory AttachmentPage.fromJson(Map<String, dynamic> value) {
    final rawAttachments = value['attachments'];
    if (rawAttachments is! List) {
      throw const FormatException('附件列表响应格式不正确');
    }
    final nextCursor = value['next_cursor'];
    if (nextCursor != null && nextCursor is! String) {
      throw const FormatException('附件游标响应格式不正确');
    }
    final normalizedCursor = (nextCursor as String?)?.trim();
    if (rawAttachments.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('附件列表响应格式不正确');
    }
    return AttachmentPage(
      attachments: rawAttachments
          .cast<Map<String, dynamic>>()
          .map(ConversationAttachment.fromJson)
          .toList(growable: false),
      nextCursor: normalizedCursor == null || normalizedCursor.isEmpty
          ? null
          : normalizedCursor,
    );
  }

  Map<String, dynamic> toJson() => {
        'attachments': attachments.map((item) => item.toJson()).toList(),
        'next_cursor': nextCursor,
      };
}

class MessageReaction {
  const MessageReaction(
      {required this.text,
      required this.count,
      required this.reactedByMe,
      this.users = const []});

  factory MessageReaction.fromJson(Map<String, dynamic> value) {
    final text = value['text'];
    final count = value['count'];
    final reactedByMe = value['reacted_by_me'];
    final users = value['users'];
    if (text is! String ||
        text.isEmpty ||
        count is! num ||
        !count.isFinite ||
        count <= 0 ||
        count % 1 != 0 ||
        (reactedByMe != null && reactedByMe is! bool) ||
        (users != null && users is! List)) {
      throw const FormatException('消息表情快照响应格式不正确');
    }
    final parsedUsers = <MessageReactionUser>[];
    if (users is List) {
      for (final item in users) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('消息表情参与者响应格式不正确');
        }
        final id = item['id'];
        if (id is! String || id.isEmpty) {
          throw const FormatException('消息表情参与者响应格式不正确');
        }
        parsedUsers.add(MessageReactionUser(
            id: id,
            name: item['name'] is String ? item['name'] as String : ''));
      }
    }
    return MessageReaction(
        text: text,
        count: count.toInt(),
        reactedByMe: reactedByMe == true,
        users: parsedUsers);
  }

  final String text;
  final int count;
  final bool reactedByMe;
  final List<MessageReactionUser> users;

  Map<String, dynamic> toJson() => {
        'text': text,
        'count': count,
        'reacted_by_me': reactedByMe,
        'users':
            users.map((user) => {'id': user.id, 'name': user.name}).toList(),
      };
}

class MessageReactionUser {
  const MessageReactionUser({required this.id, this.name = ''});

  final String id;
  final String name;
}

/// 当前用户视角下的一条消息表情快照。
class MessageReactionSnapshot {
  const MessageReactionSnapshot({
    required this.conversationId,
    required this.messageId,
    required this.reactionVersion,
    required this.reactions,
  });

  final String conversationId;
  final String messageId;
  final int reactionVersion;
  final List<MessageReaction> reactions;

  factory MessageReactionSnapshot.fromJson(
    Map<String, dynamic> value, {
    required String conversationId,
  }) {
    final messageId = value['message_id'];
    final version = value['reaction_version'];
    final reactions = value['reactions'];
    final responseConversationId = value['conversation_id'];
    if ((responseConversationId != null &&
            responseConversationId != conversationId) ||
        messageId is! String ||
        messageId.isEmpty ||
        version is! num ||
        !version.isFinite ||
        version < 0 ||
        version % 1 != 0 ||
        reactions is! List) {
      throw const FormatException('消息表情快照响应格式不正确');
    }
    final parsed = <MessageReaction>[];
    for (final item in reactions) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('消息表情快照响应格式不正确');
      }
      parsed.add(MessageReaction.fromJson(item));
    }
    return MessageReactionSnapshot(
        conversationId: conversationId,
        messageId: messageId,
        reactionVersion: version.toInt(),
        reactions: parsed);
  }

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'message_id': messageId,
        'reaction_version': reactionVersion,
        'reactions': reactions.map((reaction) => reaction.toJson()).toList(),
      };
}

class Contact {
  const Contact(
      {required this.id,
      required this.name,
      this.online = false,
      this.type = 'user',
      this.role = 'member',
      this.nickname = '',
      this.email = '',
      this.phone = '',
      this.avatar = '',
      this.joined = false,
      this.memberCount = 0,
      this.visibility = 'private',
      this.description = '',
      this.creatorUserId});
  final String id;
  final String name;
  final bool online;
  final String type;
  final String role;
  final String nickname;
  final String email;
  final String phone;
  final String avatar;
  final bool joined;
  final int memberCount;
  final String visibility;
  final String description;
  final String? creatorUserId;

  String get displayName {
    final preferred = nickname.trim();
    if (preferred.isNotEmpty && preferred != id) return preferred;
    final fallback = name.trim();
    if (fallback.isNotEmpty && fallback != id) return fallback;
    return switch (type) {
      'app' => '应用',
      'group' => '群组',
      _ => '成员',
    };
  }

  Contact copyWith({
    String? name,
    bool? online,
    String? type,
    String? role,
    String? nickname,
    String? email,
    String? phone,
    String? avatar,
    bool? joined,
    int? memberCount,
    String? visibility,
    String? description,
    String? creatorUserId,
  }) =>
      Contact(
          id: id,
          name: name ?? this.name,
          online: online ?? this.online,
          type: type ?? this.type,
          role: role ?? this.role,
          nickname: nickname ?? this.nickname,
          email: email ?? this.email,
          phone: phone ?? this.phone,
          avatar: avatar ?? this.avatar,
          joined: joined ?? this.joined,
          memberCount: memberCount ?? this.memberCount,
          visibility: visibility ?? this.visibility,
          description: description ?? this.description,
          creatorUserId: creatorUserId ?? this.creatorUserId);
}

class ContactDirectory {
  const ContactDirectory({required this.contacts, required this.mode});
  final List<Contact> contacts;
  final String mode;

  bool get supportsFriendManagement => mode == 'friends';
}

class FriendRequest {
  const FriendRequest(
      {required this.id, required this.userId, required this.status});
  final String id;
  final String userId;
  final String status;
}

class Project {
  const Project(
      {required this.id,
      required this.name,
      this.taskCount,
      this.description = '',
      this.avatar = '',
      this.isPersonal = false,
      this.updatedAt = ''});
  final String id;
  final String name;
  final int? taskCount;
  final String description;
  final String avatar;
  final bool isPersonal;
  final String updatedAt;
}

class ProjectPage {
  const ProjectPage(
      {required this.projects, this.personalProject, this.nextCursor});

  final List<Project> projects;
  final Project? personalProject;
  final String? nextCursor;
}

class ProjectGroup {
  const ProjectGroup(
      {required this.id,
      required this.name,
      this.avatar = '',
      this.status = '',
      this.memberCount = 0,
      this.createdAt = ''});

  final String id;
  final String name;
  final String avatar;
  final String status;
  final int memberCount;
  final String createdAt;
}

class ProjectTask {
  const ProjectTask(
      {required this.id,
      required this.projectId,
      required this.title,
      required this.status,
      this.priority = 2,
      this.description = '',
      this.startDate,
      this.dueDate,
      this.labels = const [],
      this.assignee,
      this.reminder});
  final String id;
  final String projectId;
  final String title;
  final String status;
  final int priority;
  final String description;
  final String? startDate;
  final String? dueDate;
  final List<String> labels;
  final ProjectUser? assignee;
  final Map<String, dynamic>? reminder;
  String? get assigneeUserId => assignee?.id;
}

class ProjectTaskPage {
  const ProjectTaskPage({required this.tasks, this.nextCursor});

  final List<ProjectTask> tasks;
  final String? nextCursor;
}

class ProjectUser {
  const ProjectUser(
      {required this.id, this.name = '', this.nickname = '', this.avatar = ''});

  final String id;
  final String name;
  final String nickname;
  final String avatar;

  String get displayName => nickname.isNotEmpty && nickname != id
      ? nickname
      : name.isNotEmpty && name != id
          ? name
          : '成员';
}

class ProjectMember extends ProjectUser {
  const ProjectMember(
      {required super.id,
      super.name,
      super.nickname,
      super.avatar,
      this.email = '',
      this.displayNameOverride = '',
      this.role = 'member',
      this.status = '',
      this.sourceGroupIds = const []});

  final String email;
  final String displayNameOverride;
  final String role;
  final String status;
  final List<String> sourceGroupIds;

  @override
  String get displayName =>
      displayNameOverride.isNotEmpty && displayNameOverride != id
          ? displayNameOverride
          : super.displayName;
}

class ProjectTaskActivityChange {
  const ProjectTaskActivityChange(
      {required this.field, required this.from, required this.to});
  final String field;
  final Object? from;
  final Object? to;
}

class ProjectTaskActivity {
  const ProjectTaskActivity(
      {required this.id,
      required this.projectId,
      required this.taskId,
      required this.type,
      required this.actor,
      required this.createdAt,
      this.content = '',
      this.changes = const []});

  final String id;
  final String projectId;
  final String taskId;
  final String type;
  final ProjectUser actor;
  final String content;
  final List<ProjectTaskActivityChange> changes;
  final String createdAt;
}

class ProjectTaskUpdate {
  const ProjectTaskUpdate(
      {required this.title,
      required this.description,
      required this.status,
      required this.priority,
      required this.startDate,
      required this.dueDate,
      required this.labels,
      required this.assigneeUserId,
      required this.reminder});

  final String title;
  final String description;
  final String status;
  final int priority;
  final String? startDate;
  final String? dueDate;
  final List<String> labels;
  final String? assigneeUserId;
  final Map<String, dynamic>? reminder;
}

class ProjectDocument {
  const ProjectDocument(
      {required this.id,
      required this.projectId,
      required this.title,
      this.kind = 'document',
      this.parentId,
      this.documentType,
      this.sortOrder = 0,
      this.schemaVersion = 1});
  final String id;
  final String projectId;
  final String title;
  final String kind;
  final String? parentId;
  final String? documentType;
  final int sortOrder;
  final int schemaVersion;
}

class CurrentUser {
  const CurrentUser(
      {required this.id,
      required this.name,
      required this.email,
      this.nickname = '',
      this.avatar = '',
      this.phone = ''});
  final String id;
  final String name;
  final String email;
  final String nickname;
  final String avatar;
  final String phone;
  String get displayName {
    final preferred = nickname.trim();
    if (preferred.isNotEmpty && preferred != id) return preferred;
    final fallback = name.trim();
    if (fallback.isNotEmpty && fallback != id) return fallback;
    final address = email.trim();
    return address.isNotEmpty && address != id ? address : '用户';
  }
}

/// 当前用户创建的应用配置。
///
/// 字段名与服务端 `/api/client/apps` 的 JSON 契约保持一致；Dart 属性仍
/// 使用 lowerCamelCase，便于 Flutter 侧调用。
class OwnedApp {
  const OwnedApp({
    required this.id,
    required this.name,
    this.description = '',
    this.avatar = '',
    this.connectionStatus = 'offline',
    this.createdAt = '',
    this.updatedAt = '',
    this.enabled = true,
    this.visibility = 'creator',
    this.userIds = const [],
  });

  final String id;
  final String name;
  final String description;
  final String avatar;
  final String connectionStatus;
  final String createdAt;
  final String updatedAt;
  final bool enabled;
  final String visibility;
  final List<String> userIds;

  factory OwnedApp.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final name = value['name'];
    final createdAt = value['created_at'];
    final updatedAt = value['updated_at'];
    final userIds = value['user_ids'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        createdAt is! String ||
        createdAt.isEmpty ||
        updatedAt is! String ||
        updatedAt.isEmpty ||
        userIds is! List ||
        userIds.any((item) => item is! String)) {
      throw const FormatException('应用响应格式不正确');
    }
    final connectionStatus = value['connection_status'];
    final visibility = value['visibility'];
    return OwnedApp(
      id: id,
      name: name,
      description:
          value['description'] is String ? value['description'] as String : '',
      avatar: value['avatar'] is String ? value['avatar'] as String : '',
      connectionStatus:
          connectionStatus == 'online' || connectionStatus == 'disabled'
              ? connectionStatus as String
              : 'offline',
      createdAt: createdAt,
      updatedAt: updatedAt,
      enabled: value['enabled'] != false,
      visibility: visibility == 'public' || visibility == 'restricted'
          ? visibility as String
          : 'creator',
      userIds: userIds.whereType<String>().toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'avatar': avatar,
        'connection_status': connectionStatus,
        'created_at': createdAt,
        'description': description,
        'enabled': enabled,
        'id': id,
        'name': name,
        'updated_at': updatedAt,
        'user_ids': userIds,
        'visibility': visibility,
      };
}

class AppCredentials {
  const AppCredentials({required this.app, required this.connectionSecret});

  final OwnedApp app;
  final String connectionSecret;

  factory AppCredentials.fromJson(Map<String, dynamic> value) {
    final app = value['app'];
    final secret = value['connection_secret'];
    if (app is! Map<String, dynamic> || secret is! String || secret.isEmpty) {
      throw const FormatException('应用接入信息响应格式不正确');
    }
    return AppCredentials(
      app: OwnedApp.fromJson(app),
      connectionSecret: secret,
    );
  }

  Map<String, dynamic> toJson() => {
        'app': app.toJson(),
        'connection_secret': connectionSecret,
      };
}
