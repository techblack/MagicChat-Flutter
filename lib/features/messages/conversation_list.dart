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

int conversationUnreadCount(ChatConversation conversation) {
  if (conversation.unread > 0) return conversation.unread;
  return conversation.lastMessageSeq > conversation.lastReadSeq ||
          conversation.lastMentionedSeq > conversation.lastReadSeq ||
          conversation.lastChoiceSeq > conversation.lastReadSeq
      ? 1
      : 0;
}

/// 批量已读需要覆盖普通消息、提及和选择题提醒中的最大序号。
int conversationReadTargetSequence(ChatConversation conversation) {
  var target = conversation.lastMessageSeq;
  if (conversation.lastMentionedSeq > target) {
    target = conversation.lastMentionedSeq;
  }
  if (conversation.lastChoiceSeq > target) {
    target = conversation.lastChoiceSeq;
  }
  return target;
}

int totalConversationUnread(Iterable<ChatConversation> conversations) =>
    conversations.fold(
        0, (total, item) => total + conversationUnreadCount(item));

bool matchesConversationQuery(ChatConversation conversation, String query) {
  final keyword = query.trim().toLowerCase();
  if (keyword.isEmpty) return true;
  return conversation.title.toLowerCase().contains(keyword) ||
      conversation.preview.toLowerCase().contains(keyword) ||
      conversation.announcement.toLowerCase().contains(keyword);
}

/// 置顶会话优先，其余按最后消息时间倒序；旧服务端缺少时间时回退到序号。
List<ChatConversation> orderConversations(
    Iterable<ChatConversation> conversations) {
  final values = conversations.toList();
  values.sort((left, right) {
    if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
    final leftAt = DateTime.tryParse(
            left.lastMessageAt.isNotEmpty ? left.lastMessageAt : left.createdAt)
        ?.toUtc();
    final rightAt = DateTime.tryParse(right.lastMessageAt.isNotEmpty
            ? right.lastMessageAt
            : right.createdAt)
        ?.toUtc();
    if (leftAt != null || rightAt != null) {
      if (leftAt == null) return 1;
      if (rightAt == null) return -1;
      final timestamp = rightAt.compareTo(leftAt);
      if (timestamp != 0) return timestamp;
    }
    final sequence = right.lastMessageSeq.compareTo(left.lastMessageSeq);
    if (sequence != 0) return sequence;
    return left.id.compareTo(right.id);
  });
  return values;
}
