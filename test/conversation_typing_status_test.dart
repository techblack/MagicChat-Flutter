import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/realtime.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';

void main() {
  test('忽略自己的输入状态并在断线时清理对端状态', () {
    final store = RealtimeStore()..setCurrentUserId('me');
    void applyStatus(String senderId) => store.apply({
          'event': 'conversation.status',
          'payload': {
            'conversation_id': 'conversation-1',
            'status': 'typing',
            'sender': {'id': senderId, 'type': 'user'},
          },
        });

    applyStatus('me');
    expect(store.conversationStatuses, isEmpty);
    applyStatus('alice');
    expect(store.conversationStatuses, hasLength(1));

    store.apply(const {
      'event': 'system.connection_lost',
      'payload': <String, dynamic>{},
    });
    expect(store.conversationStatuses, isEmpty);
    store.dispose();
  });

  testWidgets('私聊输入框聚焦后立即发送并每三秒续期', (tester) async {
    final realtime = _AutoResponseRealtime();
    final session = RealtimeSession(realtime: realtime);
    final store = RealtimeStore();
    store.conversations['conversation-1'] = _TypingRepository.direct;
    await session.connect();
    realtime.add(const {
      'kind': 'event',
      'event': 'system.ready',
      'payload': <String, dynamic>{},
    });
    await tester.pump();
    addTearDown(session.close);

    await _pumpConversation(tester,
        repository: _TypingRepository('direct'),
        session: session,
        store: store);
    await tester.tap(find.widgetWithText(TextField, '输入消息…'));
    await tester.pump();
    await tester.pump();

    expect(realtime.sent, hasLength(1));
    expect(realtime.sent.single['method'], 'conversation.status');
    expect(realtime.sent.single['payload'], {
      'conversation_id': 'conversation-1',
      'status': '正在输入',
    });

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(realtime.sent, hasLength(2));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final stoppedAt = realtime.sent.length;
    await tester.pump(const Duration(seconds: 3));
    expect(realtime.sent, hasLength(stoppedAt));
  });

  testWidgets('收到输入状态时在顶栏显示，超时或消息到达后清除', (tester) async {
    final store = RealtimeStore();
    store.conversations['conversation-1'] = _TypingRepository.direct;
    await _pumpConversation(tester,
        repository: _TypingRepository('direct'), store: store);

    store.apply(const {
      'event': 'conversation.status',
      'payload': {
        'conversation_id': 'conversation-1',
        'status': 'typing',
        'sender': {'id': 'alice', 'type': 'user'},
      },
    });
    await tester.pump();
    expect(find.text('正在输入'), findsOneWidget);
    expect(store.conversationStatuses['conversation-1']?.senderId, 'alice');

    await tester.pump(const Duration(seconds: 5, milliseconds: 1));
    expect(find.text('正在输入'), findsNothing);

    store.apply(const {
      'event': 'conversation.status',
      'payload': {
        'conversation_id': 'conversation-1',
        'status': '正在输入',
        'sender': {'id': 'alice', 'type': 'user'},
      },
    });
    await tester.pump();
    expect(find.text('正在输入'), findsOneWidget);

    store.apply(const {
      'cursor': 1,
      'event': 'message.created',
      'payload': {
        'id': 'message-1',
        'conversation_id': 'conversation-1',
        'seq': 1,
        'sender': {'id': 'alice', 'type': 'user', 'name': 'Alice'},
        'body': {'type': 'text', 'content': '已发送'},
      },
    });
    await tester.pump();
    expect(find.text('正在输入'), findsNothing);
    expect(store.conversationStatuses, isEmpty);
  });

  testWidgets('群聊不发送一对一输入状态', (tester) async {
    final realtime = _AutoResponseRealtime();
    final session = RealtimeSession(realtime: realtime);
    final store = RealtimeStore();
    store.conversations['conversation-1'] = _TypingRepository.group;
    await session.connect();
    realtime.add(const {
      'kind': 'event',
      'event': 'system.ready',
      'payload': <String, dynamic>{},
    });
    await tester.pump();
    addTearDown(session.close);

    await _pumpConversation(tester,
        repository: _TypingRepository('group'), session: session, store: store);
    await tester.tap(find.widgetWithText(TextField, '输入消息…'));
    await tester.pump(const Duration(seconds: 3));

    expect(realtime.sent, isEmpty);
  });
}

Future<void> _pumpConversation(
  WidgetTester tester, {
  required _TypingRepository repository,
  required RealtimeStore store,
  RealtimeSession? session,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MessagesPage(
        repository: repository,
        realtimeSession: session,
        realtimeStore: store,
        selectedId: 'conversation-1',
        onSelect: (_) {},
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.widgetWithText(TextField, '输入消息…'), findsOneWidget);
}

class _TypingRepository extends DemoRepository {
  _TypingRepository(this.type);

  final String type;

  static const direct = ChatConversation(
    id: 'conversation-1',
    title: 'Alice',
    type: 'direct',
    members: [Contact(id: 'alice', name: 'Alice', online: true)],
  );
  static const group = ChatConversation(
    id: 'conversation-1',
    title: '项目群',
    type: 'group',
  );

  @override
  Future<List<ChatConversation>> conversations() async =>
      [type == 'group' ? group : direct];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async =>
      type == 'group' ? const [] : direct.members;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [];
}

class _AutoResponseRealtime extends MagicChatRealtime {
  _AutoResponseRealtime()
      : super(
          serverUrl: 'https://chat.example.com',
          sessionToken: 'token',
          connector: (_, __) => throw UnimplementedError(),
        );

  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];

  void add(Map<String, dynamic> event) => controller.add(event);

  @override
  Stream<Map<String, dynamic>> connect({int? cursor}) => controller.stream;

  @override
  Future<void> send(Map<String, dynamic> envelope) async {
    sent.add(Map<String, dynamic>.from(envelope));
    controller.add({
      'kind': 'response',
      'reply_to': envelope['id'],
      'ok': true,
      'payload': <String, dynamic>{},
    });
  }

  @override
  Future<void> close() async {}
}
