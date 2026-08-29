import '../../domain/models.dart';

/// 会话列表筛选项。筛选只影响展示，不改变服务端会话状态。
enum ConversationFilter { all, unread, direct, group, app }

String conversationFilterLabel(ConversationFilter filter) => switch (filter) {
      ConversationFilter.all => '全部',
      ConversationFilter.unread => '未读',
      ConversationFilter.direct => '私聊',
      ConversationFilter.group => '群聊',
      ConversationFilter.app => '应用',
    };

bool matchesConversationFilter(
    ChatConversation conversation, ConversationFilter filter) {
  if (filter == ConversationFilter.all) return true;
  if (filter == ConversationFilter.unread) {
    return conversation.unread > 0 ||
        conversation.lastMessageSeq > conversation.lastReadSeq ||
        conversation.lastMentionedSeq > conversation.lastReadSeq ||
        conversation.lastChoiceSeq > conversation.lastReadSeq;
  }
  final type = conversation.type == 'topic'
      ? conversation.topic?.parentConversationType
      : conversation.type;
  return switch (filter) {
    ConversationFilter.direct => type == 'direct' || type == 'app',
    ConversationFilter.group => type == 'group',
    ConversationFilter.app => type == 'app',
    ConversationFilter.all || ConversationFilter.unread => false,
  };
}

bool matchesConversationQuery(ChatConversation conversation, String query) {
  final keyword = query.trim().toLowerCase();
  if (keyword.isEmpty) return true;
  return conversation.title.toLowerCase().contains(keyword) ||
      conversation.preview.toLowerCase().contains(keyword) ||
      conversation.announcement.toLowerCase().contains(keyword);
}

/// 置顶会话优先，其余按最新消息序号倒序；序号相同时用 ID 保证稳定排序。
List<ChatConversation> orderConversations(
    Iterable<ChatConversation> conversations) {
  final values = conversations.toList();
  values.sort((left, right) {
    if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
    final sequence = right.lastMessageSeq.compareTo(left.lastMessageSeq);
    if (sequence != 0) return sequence;
    return left.id.compareTo(right.id);
  });
  return values;
}
