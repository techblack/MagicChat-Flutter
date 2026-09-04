import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/realtime_message_pipeline.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  Map<String, dynamic> event() => {
        'cursor': 1,
        'event': 'message.created',
        'payload': {
          'id': 'message-1',
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
    await processing;
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
}
