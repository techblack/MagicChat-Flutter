import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-1');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('会话先展示本地消息再用远程结果刷新', (tester) async {
    final remote = Completer<List<ChatMessage>>();
    final repository = _CachePriorityRepository(remote: remote.future);
    final store = _MemoryMessageCacheStore([
      _record('cached', 1, '本地缓存消息'),
    ]);

    await _pump(tester, repository, store, scope);
    await tester.pump();
    expect(find.text('本地缓存消息'), findsOneWidget);
    expect(find.text('远程刷新消息'), findsNothing);

    remote.complete([
      const ChatMessage(
          id: 'remote',
          conversationId: 'conversation-1',
          sequence: 2,
          author: 'Alice',
          text: '远程刷新消息'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('远程刷新消息'), findsOneWidget);
    expect(store.writes, isNotEmpty);
  });

  testWidgets('首次远程消息等待缓存写入完成后展示', (tester) async {
    final writeGate = Completer<void>();
    final store = _MemoryMessageCacheStore(const [], writeGate: writeGate);
    final repository = _CachePriorityRepository(
        remote: Future.value([
      const ChatMessage(
          id: 'remote',
          conversationId: 'conversation-1',
          sequence: 1,
          author: 'Alice',
          text: '先落库再展示'),
    ]));

    await _pump(tester, repository, store, scope);
    await tester.pump();
    expect(find.text('先落库再展示'), findsNothing);

    writeGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('先落库再展示'), findsOneWidget);
  });

  testWidgets('首次远程消息缓存失败时仍然展示', (tester) async {
    final store = _MemoryMessageCacheStore(const [], failWrites: true);
    final repository = _CachePriorityRepository(
        remote: Future.value([
      const ChatMessage(
          id: 'remote',
          conversationId: 'conversation-1',
          sequence: 1,
          author: 'Alice',
          text: '缓存失败仍展示'),
    ]));

    await _pump(tester, repository, store, scope);
    await tester.pumpAndSettle();

    expect(find.text('缓存失败仍展示'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, MagicChatRepository repository,
    MessageCacheStore store, MessageCacheScope scope) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ConversationView(
        repository: repository,
        conversationId: 'conversation-1',
        cacheScope: scope,
        messageCacheStore: store,
      ),
    ),
  ));
  await tester.pump();
}

class _CachePriorityRepository extends DemoRepository {
  _CachePriorityRepository({required this.remote});

  final Future<List<ChatMessage>> remote;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) =>
      remote;

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '缓存会话'),
      ];
}

class _MemoryMessageCacheStore extends MessageCacheStore {
  _MemoryMessageCacheStore(this.records,
      {this.writeGate, this.failWrites = false});

  final List<Map<String, dynamic>> records;
  final Completer<void>? writeGate;
  final bool failWrites;
  final writes = <List<Map<String, dynamic>>>[];

  @override
  Future<List<Map<String, dynamic>>> read(
    MessageCacheScope scope,
    String conversationId, {
    String conversationType = 'direct',
    int? beforeSequence,
    int? limit,
  }) async =>
      records.map(Map<String, dynamic>.from).toList(growable: false);

  @override
  Future<void> write(
    MessageCacheScope scope,
    String conversationId,
    List<Map<String, dynamic>> messages, {
    String conversationType = 'direct',
  }) async {
    if (failWrites) throw StateError('disk full');
    final gate = writeGate;
    if (gate != null) await gate.future;
    writes.add(messages);
    records
      ..clear()
      ..addAll(messages);
  }

  @override
  Future<void> upsertAll(
    MessageCacheScope scope,
    String conversationId,
    Iterable<Map<String, dynamic>> messages, {
    String conversationType = 'direct',
  }) async {
    if (failWrites) throw StateError('disk full');
    final values = messages.toList(growable: false);
    writes.add(values);
    final byId = <String, Map<String, dynamic>>{
      for (final record in records)
        if (record['id'] is String) record['id'] as String: record,
    };
    for (final record in values) {
      final id = record['id'];
      if (id is String) byId[id] = record;
    }
    records
      ..clear()
      ..addAll(byId.values);
  }

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _record(String id, int sequence, String text) => {
      'id': id,
      'conversation_id': 'conversation-1',
      'sequence': sequence,
      'created_at': '2026-09-04T10:00:00Z',
      'author': 'Alice',
      'author_id': 'alice',
      'content_type': 'text',
      'raw_body': {'type': 'text', 'content': text},
      'text': text,
      'mine': false,
      'reactions': const [],
    };
