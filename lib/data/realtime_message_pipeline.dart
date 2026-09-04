import '../domain/models.dart';
import 'realtime_store.dart';

/// 先持久化实时消息快照，再更新可观察内存状态。
///
/// 持久化失败不会丢弃消息；事件仍会交给 [RealtimeStore] 展示。
Future<void> applyRealtimeEventAfterPersistence({
  required RealtimeStore store,
  required Map<String, dynamic> event,
  Future<void> Function(ChatMessage message)? persist,
}) async {
  final cursor = event['cursor'];
  final duplicate = cursor is num && cursor.toInt() <= store.cursor;
  final message = duplicate ? null : store.previewMessage(event);
  if (message != null && persist != null) {
    try {
      await persist(message);
    } catch (_) {
      // 缓存不可写时继续展示实时消息。
    }
  }
  store.apply(event);
}
