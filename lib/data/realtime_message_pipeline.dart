import '../domain/models.dart';
import 'realtime_store.dart';

/// 先持久化实时消息快照，再更新可观察内存状态。
///
/// 持久化失败不会丢弃消息；事件仍会交给 [RealtimeStore] 展示。
///
/// 返回值表示该事件是否可用于产生一次性通知；重复 cursor 或已存在的
/// 消息会继续幂等投影，但不应再次提醒用户。
Future<bool> applyRealtimeEventAfterPersistence({
  required RealtimeStore store,
  required Map<String, dynamic> event,
  Future<void> Function(ChatMessage message)? persist,
}) async {
  final cursor = event['cursor'];
  final duplicate = cursor is num && cursor.toInt() <= store.cursor;
  final message = duplicate ? null : store.previewMessage(event);
  final replayedMessage =
      message != null && store.messages.containsKey(message.id);
  if (message != null && persist != null) {
    try {
      await persist(message);
    } catch (_) {
      // 缓存不可写时继续展示实时消息。
    }
  }
  store.apply(event);
  return !duplicate && !replayedMessage;
}
