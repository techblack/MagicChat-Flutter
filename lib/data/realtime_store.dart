import 'package:flutter/foundation.dart';
import '../domain/message_content.dart';
import '../domain/models.dart';

/// 将 WebSocket envelope 投影为可观察状态；以消息 ID/cursor 去重，允许重复和乱序事件。
class RealtimeStore extends ChangeNotifier {
  final conversations = <String, ChatConversation>{};
  final messages = <String, ChatMessage>{};
  final contacts = <String, Contact>{};
  String? currentUserId;
  String? lastEvent;
  int cursor = 0;

  void setCurrentUserId(String? id) {
    currentUserId = id;
  }

  void reset() {
    conversations.clear();
    messages.clear();
    contacts.clear();
    currentUserId = null;
    lastEvent = null;
    cursor = 0;
    notifyListeners();
  }

  /// 在不改变当前可观察状态的前提下，计算消息事件应用后的消息快照。
  /// 实时流水线用它先持久化消息，再把原事件交给 [apply] 展示。
  ChatMessage? previewMessage(Map<String, dynamic> envelope) {
    final event = envelope['event'];
    final rawPayload = envelope['payload'];
    if (event is! String || rawPayload is! Map<String, dynamic>) return null;
    final payload = rawPayload['message'] is Map<String, dynamic>
        ? rawPayload['message'] as Map<String, dynamic>
        : rawPayload;
    final messageId = event == 'message.created' || event == 'message.updated'
        ? payload['id']
        : event == 'message.reactions_updated' ||
                event == 'message.choice_updated'
            ? payload['message_id']
            : null;
    if (messageId is! String || messageId.isEmpty) return null;

    final staged = RealtimeStore()
      ..currentUserId = currentUserId
      ..messages.addAll(messages)
      ..conversations.addAll(conversations);
    staged.apply({...envelope, 'cursor': 1});
    return staged.messages[messageId];
  }

  void markConversationRead(ConversationReadResult result) {
    final current = conversations[result.conversationId];
    if (current == null) return;
    conversations[result.conversationId] = ChatConversation(
        id: current.id,
        title: current.title,
        preview: current.preview,
        announcement: current.announcement,
        isPublic: current.isPublic,
        avatar: current.avatar,
        createdAt: current.createdAt,
        unread: result.unreadCount,
        pinned: current.pinned,
        muted: current.muted,
        lastMessageAt: current.lastMessageAt,
        lastMessageSeq: current.lastMessageSeq,
        lastReadSeq: result.lastReadSeq,
        lastMentionedSeq: current.lastMentionedSeq,
        lastChoiceSeq: current.lastChoiceSeq,
        members: current.members,
        canSend: current.canSend,
        topic: current.topic);
    notifyListeners();
  }

  void apply(Map<String, dynamic> envelope) {
    final value = envelope['cursor'];
    if (value is num && value.toInt() <= cursor) return;
    if (value is num) cursor = value.toInt();
    final event = envelope['event'];
    final payload = envelope['payload'];
    if (payload is! Map<String, dynamic> || event is! String) return;
    lastEvent = event;
    switch (event) {
      case 'message.created':
        _upsertMessage(payload, countUnread: true);
      case 'message.updated':
        _upsertMessage(payload, countUnread: false);
      case 'message.reactions_updated':
        _patchReactions(payload);
      case 'message.choice_updated':
        _patchChoice(payload);
      case 'conversation.removed':
        final id = payload['conversation_id'];
        if (id is String) conversations.remove(id);
      case 'conversation.pin_updated':
      case 'conversation.mute_updated':
        _patchConversation(payload);
      case 'conversation.member_mentioned':
      case 'conversation.member_choice_received':
        _patchConversationReminder(payload, event);
      case 'topic.created':
      case 'topic.participated':
      case 'topic.archived':
        _patchTopic(payload, event);
      case 'user.presence.updated':
        _patchPresence(payload);
    }
    notifyListeners();
  }

  void _patchPresence(Map<String, dynamic> payload) {
    final id = payload['user_id'];
    final online = payload['online'];
    if (id is! String || online is! bool) return;
    final current = contacts[id];
    if (current != null) {
      contacts[id] = Contact(
          id: current.id,
          name: current.name,
          online: online,
          type: current.type,
          role: current.role,
          nickname: current.nickname,
          email: current.email,
          phone: current.phone,
          avatar: current.avatar,
          joined: current.joined,
          memberCount: current.memberCount,
          visibility: current.visibility);
    }
  }

  void _patchReactions(Map<String, dynamic> payload) {
    final id = payload['message_id'];
    if (id is! String) return;
    final current = messages[id];
    if (current == null || current.contentType == 'revoked') return;
    final actorText = payload['actor_text'];
    final actorReacted = payload['actor_reacted'] == true;
    final actorUserId = payload['actor_user_id'];
    final reactions = payload['reactions'];
    if (reactions is! List) return;
    messages[id] = ChatMessage(
        id: current.id,
        text: current.text,
        author: current.author,
        authorId: current.authorId,
        conversationId: current.conversationId,
        sequence: current.sequence,
        createdAt: current.createdAt,
        contentType: current.contentType,
        rawBody: current.rawBody,
        mine: current.mine,
        choice: current.choice,
        replyTo: current.replyTo,
        topic: current.topic,
        editableText: current.editableText,
        reactions: reactions
            .whereType<Map<String, dynamic>>()
            .where((item) => item['text'] is String)
            .map((item) => MessageReaction(
                text: item['text'] as String,
                count: (item['count'] as num?)?.toInt() ?? 0,
                reactedByMe: actorUserId == currentUserId &&
                    actorReacted &&
                    actorText == item['text'],
                users: _reactionUsers(item['users'])))
            .where((reaction) => reaction.count > 0)
            .toList());
  }

  void _patchChoice(Map<String, dynamic> payload) {
    final id = payload['message_id'];
    if (id is! String) return;
    final current = messages[id];
    if (current == null || current.contentType != 'choice') return;
    final choice = parseMessageChoiceState(payload['choice']);
    if (choice == null) return;
    final actorId = payload['actor_user_id'];
    final actorOptionIds = payload['actor_option_ids'];
    final myOptionIds = actorId == currentUserId && actorOptionIds is List
        ? actorOptionIds
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList(growable: false)
        : current.choice?.myOptionIds ?? choice.myOptionIds;
    messages[id] = ChatMessage(
        id: current.id,
        text: current.text,
        author: current.author,
        authorId: current.authorId,
        conversationId: current.conversationId,
        sequence: current.sequence,
        createdAt: current.createdAt,
        contentType: current.contentType,
        rawBody: current.rawBody,
        mine: current.mine,
        choice: MessageChoiceState(
            myOptionIds: myOptionIds,
            options: choice.options,
            responseCount: choice.responseCount),
        replyTo: current.replyTo,
        topic: current.topic,
        editableText: current.editableText,
        reactions: current.reactions);
  }

  void _upsertMessage(Map<String, dynamic> payload,
      {required bool countUnread}) {
    final nested = payload['message'];
    if (nested is Map<String, dynamic>) payload = nested;
    final id = payload['id'];
    if (id is! String || id.isEmpty) return;
    final previous = messages[id];
    final body = MessageContent.fromEnvelope(payload['body'],
        revokedAt: payload['revoked_at']);
    final editableBody = payload['editable_body'];
    final editableText = editableBody is Map<String, dynamic>
        ? MessageContent.parse(editableBody).text
        : previous?.editableText;
    final sender = payload['sender'];
    final name = sender is Map<String, dynamic> ? sender['name'] : null;
    final nickname = sender is Map<String, dynamic> ? sender['nickname'] : null;
    final senderId = sender is Map<String, dynamic> ? sender['id'] : null;
    final conversationId = payload['conversation_id'];
    final reply = payload['reply_to'];
    final replyToMessageId = payload['reply_to_message_id'];
    final replySender = reply is Map<String, dynamic> ? reply['sender'] : null;
    final replyNickname =
        replySender is Map<String, dynamic> ? replySender['nickname'] : null;
    final replyNameValue =
        replySender is Map<String, dynamic> ? replySender['name'] : null;
    final replySenderId =
        replySender is Map<String, dynamic> ? replySender['id'] : null;
    final replyName = replyNickname is String && replyNickname.trim().isNotEmpty
        ? replyNickname.trim()
        : replyNameValue is String && replyNameValue.trim().isNotEmpty
            ? replyNameValue.trim()
            : '用户';
    final rawTopic = payload['topic'];
    final topic = rawTopic is Map<String, dynamic>
        ? MessageTopic.fromJson(rawTopic)
        : previous?.topic;
    final sequence = (payload['seq'] as num?)?.toInt() ?? previous?.sequence;
    final createdAt = payload['created_at'] is String
        ? payload['created_at'] as String
        : previous?.createdAt ?? '';
    final author = nickname is String && nickname.trim().isNotEmpty
        ? nickname.trim()
        : name is String && name.trim().isNotEmpty
            ? name.trim()
            : previous?.author != null &&
                    previous!.author.trim().isNotEmpty &&
                    previous.author != previous.authorId
                ? previous.author
                : '成员';
    final resolvedSenderId = senderId is String ? senderId : previous?.authorId;
    final resolvedConversationId =
        conversationId is String ? conversationId : previous?.conversationId;
    final replyTo = body.type == 'revoked'
        ? null
        : reply is Map<String, dynamic> && reply['id'] is String
            ? MessageReply(
                id: reply['id'] as String,
                author: replyName,
                authorId: replySenderId is String ? replySenderId : null,
                text: reply['summary'] is String &&
                        (reply['summary'] as String).isNotEmpty
                    ? reply['summary'] as String
                    : '[消息]')
            : replyToMessageId is String && replyToMessageId.trim().isNotEmpty
                ? MessageReply(
                    id: replyToMessageId.trim(), author: '成员', text: '[消息]')
                : previous?.replyTo;
    messages[id] = ChatMessage(
        id: id,
        sequence: sequence,
        createdAt: createdAt,
        conversationId: resolvedConversationId,
        authorId: resolvedSenderId,
        author: author,
        contentType: body.type,
        rawBody: body.raw,
        text: body.text,
        editableText: editableText,
        replyTo: replyTo,
        topic: topic,
        mine: resolvedSenderId == null
            ? previous?.mine ?? false
            : resolvedSenderId == currentUserId,
        choice: body.type == 'revoked'
            ? null
            : payload.containsKey('choice')
                ? parseMessageChoiceState(payload['choice'])
                : previous?.choice,
        reactions: body.type == 'revoked'
            ? const []
            : payload.containsKey('reactions')
                ? _reactions(payload['reactions'])
                : previous?.reactions ?? const []);
    _patchConversationFromMessage(resolvedConversationId, sequence, createdAt,
        body.text, resolvedSenderId,
        countUnread: countUnread);
  }

  void _patchConversationFromMessage(String? conversationId, int? sequence,
      String createdAt, String summary, String? senderId,
      {required bool countUnread}) {
    if (conversationId == null || conversationId.isEmpty) return;
    final current = conversations[conversationId];
    if (current == null) return;
    if (sequence != null && sequence < current.lastMessageSeq) return;
    final unread =
        !countUnread || (senderId != null && senderId == currentUserId)
            ? current.unread
            : current.unread + 1;
    conversations[conversationId] = ChatConversation(
        id: current.id,
        title: current.title,
        preview: summary.isNotEmpty ? summary : current.preview,
        announcement: current.announcement,
        isPublic: current.isPublic,
        avatar: current.avatar,
        createdAt: current.createdAt,
        unread: unread,
        pinned: current.pinned,
        muted: current.muted,
        lastMessageAt: createdAt.isNotEmpty ? createdAt : current.lastMessageAt,
        lastMessageSeq: sequence ?? current.lastMessageSeq,
        lastReadSeq: current.lastReadSeq,
        lastMentionedSeq: current.lastMentionedSeq,
        lastChoiceSeq: current.lastChoiceSeq,
        type: current.type,
        members: current.members,
        canSend: current.canSend,
        topic: current.topic);
  }

  List<MessageReaction> _reactions(Object? value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((item) => item['text'] is String)
          .map((item) => MessageReaction(
              text: item['text'] as String,
              count: (item['count'] as num?)?.toInt() ?? 0,
              reactedByMe: item['reacted_by_me'] == true,
              users: _reactionUsers(item['users'])))
          .where((reaction) => reaction.count > 0)
          .toList()
      : const [];

  List<MessageReactionUser> _reactionUsers(Object? value) => value is List
      ? value
          .whereType<Map<String, dynamic>>()
          .where((item) =>
              item['id'] is String && (item['id'] as String).trim().isNotEmpty)
          .map((item) => MessageReactionUser(
              id: item['id'] as String,
              name: item['name'] is String ? item['name'] as String : ''))
          .toList(growable: false)
      : const [];

  void _patchConversation(Map<String, dynamic> payload) {
    final id = payload['conversation_id'];
    if (id is! String) return;
    final current = conversations[id];
    if (current == null) return;
    conversations[id] = ChatConversation(
        id: current.id,
        title: current.title,
        preview: current.preview,
        announcement: current.announcement,
        isPublic: current.isPublic,
        avatar: current.avatar,
        createdAt: current.createdAt,
        unread: current.unread,
        pinned: payload['pinned'] is bool
            ? payload['pinned'] as bool
            : current.pinned,
        muted: payload['muted'] is bool
            ? payload['muted'] as bool
            : payload['notification_muted'] is bool
                ? payload['notification_muted'] as bool
                : current.muted,
        lastMessageAt: payload['last_message_at'] is String
            ? payload['last_message_at'] as String
            : current.lastMessageAt,
        lastMessageSeq: (payload['last_message_seq'] as num?)?.toInt() ??
            current.lastMessageSeq,
        lastReadSeq: current.lastReadSeq,
        lastMentionedSeq: current.lastMentionedSeq,
        lastChoiceSeq: current.lastChoiceSeq,
        type: current.type,
        members: current.members,
        canSend: current.canSend,
        topic: current.topic);
  }

  void _patchConversationReminder(Map<String, dynamic> payload, String event) {
    final id = payload['conversation_id'];
    final sequence = event == 'conversation.member_mentioned'
        ? payload['last_mentioned_seq']
        : payload['last_choice_seq'];
    if (id is! String || sequence is! num) return;
    final current = conversations[id];
    if (current == null) return;
    final value = sequence.toInt();
    if (value <= 0) return;
    conversations[id] = ChatConversation(
        id: current.id,
        title: current.title,
        preview: current.preview,
        announcement: current.announcement,
        isPublic: current.isPublic,
        avatar: current.avatar,
        createdAt: current.createdAt,
        unread: current.unread,
        pinned: current.pinned,
        muted: current.muted,
        lastMessageAt: current.lastMessageAt,
        lastMessageSeq: current.lastMessageSeq,
        lastReadSeq: current.lastReadSeq,
        lastMentionedSeq: event == 'conversation.member_mentioned'
            ? value > current.lastMentionedSeq
                ? value
                : current.lastMentionedSeq
            : current.lastMentionedSeq,
        lastChoiceSeq: event == 'conversation.member_choice_received'
            ? value > current.lastChoiceSeq
                ? value
                : current.lastChoiceSeq
            : current.lastChoiceSeq,
        type: current.type,
        members: current.members,
        canSend: current.canSend,
        topic: current.topic);
  }

  void _patchTopic(Map<String, dynamic> payload, String event) {
    final id = payload['conversation_id'];
    final parentId = payload['parent_conversation_id'];
    final sourceId = payload['source_message_id'];
    if (id is! String ||
        id.isEmpty ||
        parentId is! String ||
        parentId.isEmpty ||
        sourceId is! String ||
        sourceId.isEmpty) return;
    final archived = payload['archived'] == true;
    final current = conversations[id];
    final topic = current?.topic;
    if (current == null || topic == null) return;
    if (topic.parentConversationId != parentId ||
        topic.sourceMessageId != sourceId) return;
    conversations[id] = ChatConversation(
        id: current.id,
        title: current.title,
        preview: current.preview,
        announcement: current.announcement,
        isPublic: current.isPublic,
        avatar: current.avatar,
        createdAt: current.createdAt,
        unread: current.unread,
        pinned: current.pinned,
        muted: current.muted,
        lastMessageAt: current.lastMessageAt,
        lastMessageSeq: current.lastMessageSeq,
        lastReadSeq: current.lastReadSeq,
        lastMentionedSeq: current.lastMentionedSeq,
        lastChoiceSeq: current.lastChoiceSeq,
        type: current.type,
        members: current.members,
        canSend: current.canSend && !archived,
        topic: TopicMetadata(
            archived: archived,
            parentConversationId: topic.parentConversationId,
            parentConversationName: topic.parentConversationName,
            parentConversationType: topic.parentConversationType,
            participating:
                event == 'topic.participated' ? true : topic.participating,
            sourceMessageId: topic.sourceMessageId,
            sourceMessageSeq: topic.sourceMessageSeq,
            sourceSender: topic.sourceSender));
  }
}
