import '../domain/message_content.dart';
import '../domain/models.dart';
import 'chat_preferences.dart';

const maxDesktopTrayMessages = 20;

class DesktopTrayMessageItem {
  const DesktopTrayMessageItem({
    required this.conversationId,
    required this.label,
  });

  final String conversationId;
  final String label;
}

List<DesktopTrayMessageItem> desktopTrayMessages(
  Iterable<ChatConversation> conversations,
  MessageNotificationPrivacy privacy, {
  Map<String, Contact> contacts = const {},
}) {
  final unread = conversations
      .where((conversation) => _trayUnreadCount(conversation) > 0)
      .toList()
    ..sort(_compareTrayConversations);
  return unread.take(maxDesktopTrayMessages).map((conversation) {
    final count = _trayUnreadCount(conversation);
    final name = privacy == MessageNotificationPrivacy.hidden
        ? '新消息'
        : _truncateTrayText(conversation.displayTitle, 16, fallback: '未命名会话');
    final summary = switch (privacy) {
      MessageNotificationPrivacy.hidden => '你收到了一条新消息',
      MessageNotificationPrivacy.metadata => '有新消息',
      MessageNotificationPrivacy.preview => _truncateTrayText(
          formatMentionText(
              conversation.preview, _trayMentionLabels(conversation, contacts)),
          24,
          fallback: '有新消息'),
    };
    return DesktopTrayMessageItem(
      conversationId: conversation.id,
      label: '$name  [${_trayBadge(count)}] — $summary',
    );
  }).toList(growable: false);
}

Iterable<({String id, String name})> _trayMentionLabels(
    ChatConversation conversation, Map<String, Contact> contacts) sync* {
  final ids = RegExp(r'\{\(@(?:user|app)/([^}]+)\)\}')
      .allMatches(conversation.preview)
      .map((match) => match.group(1))
      .whereType<String>()
      .where((id) => id.isNotEmpty && id != 'all')
      .toSet();
  if (ids.isEmpty) return;
  final members = <String, Contact>{
    for (final member in conversation.members)
      if (ids.contains(member.id)) member.id: member,
  };
  for (final id in ids) {
    final contact = members[id] ?? contacts[id];
    if (contact != null) yield (id: id, name: contact.displayName);
  }
}

String desktopTrayToolTip(int unreadCount) {
  final normalized = unreadCount.clamp(0, 9999);
  return normalized == 0 ? 'MagicChat' : 'MagicChat（$normalized 条未读）';
}

int _trayUnreadCount(ChatConversation conversation) {
  if (conversation.unread > 0) return conversation.unread;
  return conversation.lastMessageSeq > conversation.lastReadSeq ||
          conversation.lastMentionedSeq > conversation.lastReadSeq ||
          conversation.lastChoiceSeq > conversation.lastReadSeq
      ? 1
      : 0;
}

int _compareTrayConversations(ChatConversation left, ChatConversation right) {
  final leftAt = DateTime.tryParse(left.lastMessageAt)?.toUtc();
  final rightAt = DateTime.tryParse(right.lastMessageAt)?.toUtc();
  if (leftAt != null || rightAt != null) {
    if (leftAt == null) return 1;
    if (rightAt == null) return -1;
    final byTime = rightAt.compareTo(leftAt);
    if (byTime != 0) return byTime;
  }
  final bySequence = right.lastMessageSeq.compareTo(left.lastMessageSeq);
  return bySequence != 0 ? bySequence : left.id.compareTo(right.id);
}

String _trayBadge(int value) => value > 99 ? '99+' : '$value';

String _truncateTrayText(String value, int limit, {required String fallback}) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return fallback;
  final runes = normalized.runes.toList(growable: false);
  return runes.length <= limit
      ? normalized
      : '${String.fromCharCodes(runes.take(limit))}…';
}
