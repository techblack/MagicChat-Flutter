import 'dart:async';

import 'package:flutter/foundation.dart';
import 'contact_directory_realtime_sync.dart';
import '../domain/message_content.dart';
import '../domain/models.dart';

/// 将 WebSocket envelope 投影为可观察状态；以消息 ID/cursor 去重，允许重复和乱序事件。
class RealtimeStore extends ChangeNotifier {
  RealtimeStore({this.conversationStatusTtl = const Duration(seconds: 5)});

  final Duration conversationStatusTtl;
  final conversations = <String, ChatConversation>{};
  final messages = <String, ChatMessage>{};
  final contacts = <String, Contact>{};
  final conversationStatuses = <String, RealtimeConversationStatus>{};
  final _conversationStatusTimers = <String, Timer>{};
  String? currentUserId;
  String? lastEvent;
  String? lastProfileUpdatedUserId;
  Contact? lastResolvedUserProfile;
  int userProfileRevision = 0;
  int friendDataRevision = 0;
  int contactDirectoryRevision = 0;
  FriendDataRefreshIntent? lastFriendDataRefreshIntent;
  int cursor = 0;

  void setCurrentUserId(String? id) {
    currentUserId = id;
  }

  void reset() {
    for (final timer in _conversationStatusTimers.values) {
      timer.cancel();
    }
    _conversationStatusTimers.clear();
    conversationStatuses.clear();
    conversations.clear();
    messages.clear();
    contacts.clear();
    currentUserId = null;
    lastEvent = null;
    lastProfileUpdatedUserId = null;
    lastResolvedUserProfile = null;
    userProfileRevision = 0;
    friendDataRevision = 0;
    contactDirectoryRevision = 0;
    lastFriendDataRefreshIntent = null;
    cursor = 0;
    notifyListeners();
  }

  void replaceConversation(ChatConversation conversation) {
    conversations[conversation.id] = conversation;
    notifyListeners();
  }

  void replaceUserProfile(Contact profile) {
    if (profile.type != 'user' || profile.id.trim().isEmpty) return;
    final profileId = profile.id.trim().toLowerCase();
    MapEntry<String, Contact>? existingEntry;
    for (final entry in contacts.entries) {
      if (entry.key.trim().toLowerCase() == profileId) {
        existingEntry = entry;
        break;
      }
    }
    final resolved = existingEntry == null
        ? profile
        : _contactWithProfile(existingEntry.value, profile);
    if (existingEntry != null && existingEntry.key != resolved.id) {
      contacts.remove(existingEntry.key);
    }
    contacts[resolved.id] = resolved;
    for (final entry in conversations.entries.toList(growable: false)) {
      final conversation = entry.value;
      var matched = false;
      Contact? updatedPeer;
      final members = conversation.members.map((member) {
        if (member.type != 'user' ||
            member.id.trim().toLowerCase() != profileId) return member;
        matched = true;
        final updated = _contactWithProfile(member, profile);
        if (member.id.trim().toLowerCase() !=
            (currentUserId ?? '').trim().toLowerCase()) updatedPeer = updated;
        return updated;
      }).toList(growable: false);
      final source = conversation.topic?.sourceSender;
      final sourceMatched = source?.type == 'user' &&
          source!.id.trim().toLowerCase() == profileId;
      if (!matched && !sourceMatched) continue;
      conversations[entry.key] = _conversationWithProfile(conversation,
          members: members,
          directPeer: conversation.type == 'direct' ? updatedPeer : null,
          sourceProfile: sourceMatched ? profile : null);
    }
    lastResolvedUserProfile = resolved;
    userProfileRevision++;
    notifyListeners();
  }

  void removeConversation(String conversationId) {
    _clearConversationStatus(conversationId, notify: false);
    conversations.remove(conversationId);
    messages
        .removeWhere((_, message) => message.conversationId == conversationId);
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
        memberCount: current.memberCount,
        members: current.members,
        projects: current.projects,
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
        _clearConversationStatusForMessage(payload);
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
      case 'conversation.status':
        _patchConversationStatus(payload);
      case 'system.connection_lost':
        _clearConversationStatuses();
      case 'topic.created':
      case 'topic.participated':
      case 'topic.archived':
        _patchTopic(payload, event);
      case 'user.presence.updated':
        _patchPresence(payload);
      case 'user.profile.updated':
        _recordProfileUpdate(payload);
      case 'friend.request.created':
      case 'friend.request.updated':
      case 'friendship.created':
      case 'friendship.deleted':
      case 'contact.directory.mode.updated':
        _recordFriendDataEvent(event, payload);
    }
    notifyListeners();
  }

  void _recordFriendDataEvent(String event, Map<String, dynamic> payload) {
    final intent = switch (event) {
      'friend.request.created' ||
      'friend.request.updated' =>
        _isValidFriendRequestEvent(payload)
            ? FriendDataRefreshIntent.requests
            : null,
      'friendship.created' ||
      'friendship.deleted' =>
        _isValidFriendshipEvent(payload)
            ? FriendDataRefreshIntent.directory
            : null,
      'contact.directory.mode.updated' => _isValidDirectoryModeEvent(payload)
          ? FriendDataRefreshIntent.directory
          : null,
      _ => null,
    };
    if (intent == null) {
      return;
    }
    lastFriendDataRefreshIntent = intent;
    friendDataRevision++;
    if (intent == FriendDataRefreshIntent.directory) {
      contactDirectoryRevision++;
    }
  }

  bool _isValidFriendRequestEvent(Map<String, dynamic> payload) =>
      payload['request_id'] is String &&
      (payload['request_id'] as String).trim().isNotEmpty;

  bool _isValidFriendshipEvent(Map<String, dynamic> payload) =>
      !payload.containsKey('request_id') ||
      (payload['request_id'] is String &&
          (payload['request_id'] as String).trim().isNotEmpty);

  bool _isValidDirectoryModeEvent(Map<String, dynamic> payload) =>
      payload['mode'] == 'organization' || payload['mode'] == 'friends';

  void _patchConversationStatus(Map<String, dynamic> payload) {
    final conversationId = payload['conversation_id'];
    final rawStatus = payload['status'];
    final sender = payload['sender'];
    if (conversationId is! String ||
        conversationId.isEmpty ||
        rawStatus is! String ||
        sender is! Map<String, dynamic>) {
      return;
    }
    final senderId = sender['id'];
    final senderType = sender['type'];
    final status = rawStatus.trim();
    if (senderId is! String ||
        senderId.isEmpty ||
        senderId == currentUserId ||
        (senderType != 'user' && senderType != 'app') ||
        status.isEmpty ||
        status.runes.length > 32) {
      return;
    }
    _conversationStatusTimers.remove(conversationId)?.cancel();
    conversationStatuses[conversationId] = RealtimeConversationStatus(
      text: status == 'typing' ? '正在输入' : status,
      senderId: senderId,
      senderType: senderType as String,
    );
    _conversationStatusTimers[conversationId] = Timer(
        conversationStatusTtl, () => _clearConversationStatus(conversationId));
  }

  void _clearConversationStatusForMessage(Map<String, dynamic> payload) {
    final nested = payload['message'];
    final message = nested is Map<String, dynamic> ? nested : payload;
    final conversationId = message['conversation_id'];
    final sender = message['sender'];
    if (conversationId is! String || sender is! Map<String, dynamic>) return;
    final current = conversationStatuses[conversationId];
    if (current == null ||
        current.senderId != sender['id'] ||
        current.senderType != sender['type']) {
      return;
    }
    _clearConversationStatus(conversationId, notify: false);
  }

  void _clearConversationStatus(String conversationId, {bool notify = true}) {
    _conversationStatusTimers.remove(conversationId)?.cancel();
    final removed = conversationStatuses.remove(conversationId) != null;
    if (removed && notify) notifyListeners();
  }

  void _clearConversationStatuses() {
    for (final timer in _conversationStatusTimers.values) {
      timer.cancel();
    }
    _conversationStatusTimers.clear();
    conversationStatuses.clear();
  }

  @override
  void dispose() {
    _clearConversationStatuses();
    super.dispose();
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

  void _recordProfileUpdate(Map<String, dynamic> payload) {
    final userId = payload['user_id'];
    lastProfileUpdatedUserId =
        userId is String && userId.trim().isNotEmpty ? userId.trim() : null;
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
        clientMessageId: current.clientMessageId,
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
        editableContentType: current.editableContentType,
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
        clientMessageId: current.clientMessageId,
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
        editableContentType: current.editableContentType,
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
    final editableContent = editableBody is Map<String, dynamic>
        ? MessageContent.parse(editableBody)
        : null;
    final sender = payload['sender'];
    final name = sender is Map<String, dynamic> ? sender['name'] : null;
    final nickname = sender is Map<String, dynamic> ? sender['nickname'] : null;
    final senderId = sender is Map<String, dynamic> ? sender['id'] : null;
    final conversationId = payload['conversation_id'];
    final reply = payload['reply_to'];
    final replyToMessageId = payload['reply_to_message_id'];
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
        : reply is Map<String, dynamic>
            ? _parseReply(reply) ?? previous?.replyTo
            : replyToMessageId is String && replyToMessageId.trim().isNotEmpty
                ? MessageReply(
                    id: replyToMessageId.trim(), author: '成员', text: '[消息]')
                : previous?.replyTo;
    messages[id] = ChatMessage(
        id: id,
        clientMessageId: payload['client_message_id'] is String
            ? payload['client_message_id'] as String
            : previous?.clientMessageId,
        sequence: sequence,
        createdAt: createdAt,
        conversationId: resolvedConversationId,
        authorId: resolvedSenderId,
        author: author,
        contentType: body.type,
        rawBody: body.raw,
        text: body.text,
        editableText: editableContent?.text ?? previous?.editableText,
        editableContentType:
            editableContent?.type ?? previous?.editableContentType,
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

  MessageReply? _parseReply(Map<String, dynamic> value) {
    try {
      return MessageReply.fromJson(value);
    } on FormatException {
      return null;
    }
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
        memberCount: current.memberCount,
        members: current.members,
        projects: current.projects,
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
        memberCount: current.memberCount,
        members: current.members,
        projects: current.projects,
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
        memberCount: current.memberCount,
        members: current.members,
        projects: current.projects,
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
        memberCount: current.memberCount,
        members: current.members,
        projects: current.projects,
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

class RealtimeConversationStatus {
  const RealtimeConversationStatus({
    required this.text,
    required this.senderId,
    required this.senderType,
  });

  final String text;
  final String senderId;
  final String senderType;
}

Contact _contactWithProfile(Contact current, Contact profile) => Contact(
      id: profile.id,
      name: profile.name,
      online: profile.online,
      type: 'user',
      role: current.role,
      nickname: profile.nickname,
      email: profile.email,
      phone: profile.phone,
      avatar: profile.avatar,
      joined: current.joined,
      memberCount: current.memberCount,
      visibility: current.visibility,
      description: current.description,
      creatorUserId: current.creatorUserId,
    );

ChatConversation _conversationWithProfile(ChatConversation conversation,
    {required List<Contact> members,
    Contact? directPeer,
    Contact? sourceProfile}) {
  final topic = conversation.topic;
  final source = topic?.sourceSender;
  return ChatConversation(
      id: conversation.id,
      title: directPeer?.displayName ?? conversation.title,
      preview: conversation.preview,
      announcement: conversation.announcement,
      isPublic: conversation.isPublic,
      avatar: directPeer?.avatar ?? conversation.avatar,
      createdAt: conversation.createdAt,
      unread: conversation.unread,
      pinned: conversation.pinned,
      muted: conversation.muted,
      lastMessageAt: conversation.lastMessageAt,
      lastMessageSeq: conversation.lastMessageSeq,
      lastReadSeq: conversation.lastReadSeq,
      lastMentionedSeq: conversation.lastMentionedSeq,
      lastChoiceSeq: conversation.lastChoiceSeq,
      type: conversation.type,
      memberCount: conversation.memberCount,
      members: members,
      projects: conversation.projects,
      canSend: conversation.canSend,
      topic: topic == null || source == null || sourceProfile == null
          ? topic
          : TopicMetadata(
              archived: topic.archived,
              parentConversationId: topic.parentConversationId,
              parentConversationName: topic.parentConversationName,
              parentConversationType: topic.parentConversationType,
              participating: topic.participating,
              sourceMessageId: topic.sourceMessageId,
              sourceMessageSeq: topic.sourceMessageSeq,
              sourceSender: TopicSourceSender(
                  id: sourceProfile.id,
                  type: 'user',
                  name: sourceProfile.displayName,
                  avatar: sourceProfile.avatar)));
}
