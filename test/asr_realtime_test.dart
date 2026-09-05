import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/asr_realtime.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('构造带服务器路径的 ASR WebSocket 地址', () {
    expect(buildAsrWebSocketUri('https://chat.example.com/base'),
        Uri.parse('wss://chat.example.com/base/api/client/asr/realtime'));
  });

  test('等待 ready 后发送排队 PCM，并提交和接收识别文字', () async {
    final channel = _FakeChannel();
    Uri? connectedUri;
    String? connectedToken;
    final client = AsrRealtimeClient(
      serverUrl: 'https://chat.example.com/base',
      sessionToken: 'session-token',
      connector: (uri, token) {
        connectedUri = uri;
        connectedToken = token;
        return channel;
      },
    );
    final transcripts = <String>[];
    final subscription = client.transcripts.listen(transcripts.add);

    final connecting = client.connect();
    await Future<void>.delayed(Duration.zero);
    client.sendAudio(Uint8List.fromList([1, 2, 3, 4]));
    expect(channel.sent, isEmpty);
    channel.emit(jsonEncode(const {'type': 'ready'}));
    await connecting;

    expect(connectedUri,
        Uri.parse('wss://chat.example.com/base/api/client/asr/realtime'));
    expect(connectedToken, 'session-token');
    expect(channel.sent.single, isA<Uint8List>());
    expect(channel.sent.single, [1, 2, 3, 4]);

    final completed = client.commit();
    expect(jsonDecode(channel.sent.last as String), {'type': 'commit'});
    channel.emit(jsonEncode(const {'type': 'transcript', 'text': '你好'}));
    channel.emit(jsonEncode(const {'type': 'completed', 'text': '你好世界'}));

    expect(await completed, '你好世界');
    expect(transcripts, ['你好']);
    expect(client.state, AsrRealtimeState.completed);
    await subscription.cancel();
    await client.close();
  });

  test('服务端错误以可读异常结束提交', () async {
    final channel = _FakeChannel();
    final client = AsrRealtimeClient(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'token',
        connector: (_, __) => channel);
    final connecting = client.connect();
    await Future<void>.delayed(Duration.zero);
    channel.emit(jsonEncode(const {'type': 'ready'}));
    await connecting;

    final completed = client.commit();
    channel
        .emit(jsonEncode(const {'type': 'error', 'message': '当前服务器未启用语音识别'}));
    await expectLater(
        completed,
        throwsA(isA<AsrRealtimeException>()
            .having((error) => error.message, 'message', '当前服务器未启用语音识别')));
    await client.close();
  });
}

class _FakeChannel implements WebSocketChannel {
  final sent = <Object?>[];
  final _incoming = StreamController<Object?>();
  late final WebSocketSink _sink = _FakeSink(sent);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<Object?> get stream => _incoming.stream;

  void emit(Object? value) => _incoming.add(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.sent);

  final List<Object?> sent;
  final _done = Completer<void>();

  @override
  void add(Object? event) => sent.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
