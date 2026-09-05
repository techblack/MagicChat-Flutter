import 'dart:convert';

import '../domain/models.dart';

const messageCacheConversationTypes = <String>{
  'direct',
  'group',
  'app',
  'topic',
};

/// Identifies the account that owns a local conversation cache.
class MessageCacheScope {
  const MessageCacheScope({required this.serverUrl, required this.userId});

  final String serverUrl;
  final String userId;

  @override
  bool operator ==(Object other) =>
      other is MessageCacheScope &&
      other.serverUrl == serverUrl &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(serverUrl, userId);
}

String normalizeMessageCacheConversationType(String value) {
  final normalized = value.trim().toLowerCase();
  if (!messageCacheConversationTypes.contains(normalized)) {
    throw ArgumentError.value(value, 'conversationType', '不支持的会话类型');
  }
  return normalized;
}

String messageCachePreferenceKey(
    MessageCacheScope scope, String conversationId, String conversationType,
    {String prefix = 'magicchat.message-cache.v1.'}) {
  final type = normalizeMessageCacheConversationType(conversationType);
  final parts = [
    scope.serverUrl.trim(),
    scope.userId.trim(),
    if (type != 'direct') type,
    conversationId,
  ];
  return '$prefix${parts.map(_encodeCacheKeyPart).join('.')}';
}

String legacyMessageCachePreferenceKey(
        MessageCacheScope scope, String conversationId) =>
    messageCachePreferenceKey(scope, conversationId, 'direct');

String _encodeCacheKeyPart(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

/// Serializes a domain message into the stable cache record consumed by the UI.
Map<String, dynamic> messageCacheRecord(ChatMessage message) => {
      'id': message.id,
      'client_message_id': message.clientMessageId,
      'author': message.author,
      'author_id': message.authorId,
      'conversation_id': message.conversationId,
      'sequence': message.sequence,
      'created_at': message.createdAt,
      'content_type': message.contentType,
      'raw_body': message.rawBody,
      'text': message.text,
      if (message.editableText != null) 'editable_text': message.editableText,
      'mine': message.mine,
      if (message.choice != null)
        'choice': {
          'my_option_ids': message.choice!.myOptionIds,
          'response_count': message.choice!.responseCount,
          'options': message.choice!.options
              .map((option) => {
                    'id': option.id,
                    'response_count': option.responseCount,
                  })
              .toList(),
        },
      'reply_to': message.replyTo == null
          ? null
          : {
              'id': message.replyTo!.id,
              'author': message.replyTo!.author,
              'author_id': message.replyTo!.authorId,
              if (message.replyTo!.sequence != null)
                'sequence': message.replyTo!.sequence,
              'text': message.replyTo!.text,
            },
      if (message.topic != null) 'topic': message.topic!.toJson(),
      'reactions': message.reactions
          .map((reaction) => {
                'text': reaction.text,
                'count': reaction.count,
                'reacted_by_me': reaction.reactedByMe,
                'users': reaction.users
                    .map((user) => {
                          'id': user.id,
                          if (user.name.isNotEmpty) 'name': user.name,
                        })
                    .toList(),
              })
          .toList(),
    };
