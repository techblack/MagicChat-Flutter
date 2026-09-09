import '../domain/models.dart';
import 'message_cache_store.dart';
import 'repository.dart';

/// 在会话列表空闲时预热最近会话的首屏消息。
///
/// 预热是尽力而为的后台任务：不会阻塞会话列表，也不会覆盖已有缓存；
/// 新一轮会话列表或账号切换会使旧任务失效，避免把旧账号消息写入当前缓存。
class ConversationMessagePreloader {
  ConversationMessagePreloader({
    required MagicChatRepository repository,
    required MessageCacheStore cacheStore,
    this.maxConcurrent = 3,
    this.maxConversations = 12,
    this.messageLimit = 20,
  })  : _repository = repository,
        _cacheStore = cacheStore;

  final MagicChatRepository _repository;
  final MessageCacheStore _cacheStore;
  final int maxConcurrent;
  final int maxConversations;
  final int messageLimit;
  int _generation = 0;

  Future<void> preload({
    required MessageCacheScope scope,
    required Iterable<ChatConversation> conversations,
    String? excludeConversationId,
  }) {
    final generation = ++_generation;
    final excluded = excludeConversationId?.trim();
    final candidates = orderConversationsForPreload(conversations)
        .where((conversation) =>
            excluded == null || excluded.isEmpty || conversation.id != excluded)
        .take(maxConversations)
        .toList(growable: false);
    if (candidates.isEmpty) return Future<void>.value();

    var nextIndex = 0;
    Future<void> worker() async {
      while (generation == _generation) {
        final index = nextIndex++;
        if (index >= candidates.length) return;
        final conversation = candidates[index];
        try {
          final type = normalizeMessageCacheConversationType(conversation.type);
          final cached = await _cacheStore.read(scope, conversation.id,
              conversationType: type, limit: 1);
          if (cached.isNotEmpty || generation != _generation) continue;
          final messages =
              await _repository.messages(conversation.id, limit: messageLimit);
          if (messages.isEmpty || generation != _generation) continue;
          await _cacheStore.upsertAll(
              scope, conversation.id, messages.map(messageCacheRecord),
              conversationType: type);
        } catch (_) {
          // 预热失败不影响用户打开会话时的正常请求。
        }
      }
    }

    final workerCount = maxConcurrent < 1
        ? 1
        : maxConcurrent > candidates.length
            ? candidates.length
            : maxConcurrent;
    return Future.wait(
        List<Future<void>>.generate(workerCount, (_) => worker()));
  }

  void cancel() {
    _generation++;
  }
}

/// 预热顺序与会话列表一致，置顶会话和最近活跃会话优先。
List<ChatConversation> orderConversationsForPreload(
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
      final byTime = rightAt.compareTo(leftAt);
      if (byTime != 0) return byTime;
    }
    final bySequence = right.lastMessageSeq.compareTo(left.lastMessageSeq);
    return bySequence != 0 ? bySequence : left.id.compareTo(right.id);
  });
  return values;
}
