import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/realtime.dart';

void main() {
  test('系统就绪后发送请求并按 reply_to 匹配响应', () async {
    final realtime = _FakeRealtime();
    final session = RealtimeSession(realtime: realtime);
    await session.connect();
    await session.reconnect();
    expect(realtime.connectCount, 2);

    await expectLater(session.sendRequest('conversation.status', const {}),
        throwsA(isA<StateError>()));

    realtime.add(const {
      'v': 1,
      'kind': 'event',
      'event': 'system.ready',
      'payload': <String, dynamic>{},
    });
    await Future<void>.delayed(Duration.zero);
    expect(session.ready, isTrue);

    final result = session.sendRequest('conversation.status', const {
      'conversation_id': 'conversation-1',
      'status': '正在输入',
    });
    await Future<void>.delayed(Duration.zero);
    final request = realtime.sent.single;
    expect(request['v'], 1);
    expect(request['kind'], 'request');
    expect(request['method'], 'conversation.status');
    expect(request['id'], isA<String>());

    realtime.add({
      'v': 1,
      'kind': 'response',
      'reply_to': request['id'],
      'ok': true,
      'payload': {'accepted': true},
    });
    expect(await result, {'accepted': true});
    await session.close();
  });

  test('实时错误响应返回可读错误', () async {
    final realtime = _FakeRealtime();
    final session = RealtimeSession(realtime: realtime);
    await session.connect();
    realtime.add(const {
      'kind': 'event',
      'event': 'system.ready',
      'payload': <String, dynamic>{},
    });
    await Future<void>.delayed(Duration.zero);

    final result = session.sendRequest('conversation.status', const {});
    await Future<void>.delayed(Duration.zero);
    realtime.add({
      'kind': 'response',
      'reply_to': realtime.sent.single['id'],
      'ok': false,
      'error': {'code': 'forbidden', 'message': '无权访问该会话'},
    });

    await expectLater(
        result,
        throwsA(isA<RealtimeRequestException>()
            .having((error) => error.message, 'message', '无权访问该会话')));
    await session.close();
  });

  test('连接关闭时结束未完成请求', () async {
    final realtime = _FakeRealtime();
    final session = RealtimeSession(realtime: realtime);
    await session.connect();
    realtime.add(const {
      'kind': 'event',
      'event': 'system.ready',
      'payload': <String, dynamic>{},
    });
    await Future<void>.delayed(Duration.zero);

    final result = session.sendRequest('conversation.status', const {});
    final expectation = expectLater(result, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    await session.close();
    await expectation;
    expect(session.ready, isFalse);
  });
}

class _FakeRealtime extends MagicChatRealtime {
  _FakeRealtime()
      : super(
          serverUrl: 'https://chat.example.com',
          sessionToken: 'token',
          connector: (_, __) => throw UnimplementedError(),
        );

  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  var connectCount = 0;

  void add(Map<String, dynamic> event) => controller.add(event);

  @override
  Stream<Map<String, dynamic>> connect({int? cursor}) {
    connectCount++;
    return controller.stream;
  }

  @override
  Future<void> send(Map<String, dynamic> envelope) async {
    sent.add(Map<String, dynamic>.from(envelope));
  }

  @override
  Future<void> close() async {}
}
