import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/realtime_message_pipeline.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  Map<String, dynamic> event({int cursor = 1, String id = 'message-1'}) => {
        'cursor': cursor,
        'event': 'message.created',
        'payload': {
          'id': id,
          'conversation_id': 'conversation-1',
          'seq': 1,
          'sender': {'id': 'user-1', 'name': 'Alice'},
          'body': {'type': 'text', 'content': '先写入缓存'}
        }
      };

  test('实时消息完成持久化后才通知界面', () async {
    final store = RealtimeStore();
    final persisted = Completer<void>();
    ChatMessage? cached;
    final processing = applyRealtimeEventAfterPersistence(
      store: store,
      event: event(),
      persist: (message) async {
        cached = message;
        await persisted.future;
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(cached?.text, '先写入缓存');
    expect(store.messages, isEmpty);

    persisted.complete();
    expect(await processing, isTrue);
    expect(store.messages['message-1']?.text, '先写入缓存');
  });

  test('实时消息持久化失败时仍然展示', () async {
    final store = RealtimeStore();
    await applyRealtimeEventAfterPersistence(
      store: store,
      event: event(),
      persist: (_) async => throw StateError('disk full'),
    );

    expect(store.messages['message-1']?.text, '先写入缓存');
  });

  test('重复 cursor 和已投影消息不再产生通知', () async {
    final store = RealtimeStore();

    expect(
        await applyRealtimeEventAfterPersistence(store: store, event: event()),
        isTrue);
    expect(
        await applyRealtimeEventAfterPersistence(store: store, event: event()),
        isFalse);
    expect(
        await applyRealtimeEventAfterPersistence(
            store: store, event: event(cursor: 2)),
        isFalse);
    expect(
        await applyRealtimeEventAfterPersistence(
            store: store, event: event(cursor: 3, id: 'message-2')),
        isTrue);
  });
}
