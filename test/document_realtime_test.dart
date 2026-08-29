import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_realtime.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('认证帧符合 Hocuspocus v4 路由和认证字段顺序', () {
    final frame = encodeHocuspocusAuthenticationFrame(
        documentName: '文档-1', token: 'session-cookie');
    final reader = _FrameReader(frame);

    expect(reader.string(), '文档-1');
    expect(reader.varUint(), HocuspocusMessageType.auth);
    expect(reader.varUint(), 0); // AuthMessageType.Token
    expect(reader.string(), 'session-cookie');
    expect(reader.string(), hocuspocusProtocolVersion);
    expect(reader.remaining, 0);
  });

  test('空状态向量同步帧请求完整 Yjs 状态', () {
    final frame = encodeHocuspocusSyncStepOneFrame(documentName: 'doc');
    final reader = _FrameReader(frame);

    expect(reader.string(), 'doc');
    expect(reader.varUint(), HocuspocusMessageType.sync);
    expect(reader.varUint(), 0); // messageYjsSyncStep1
    expect(reader.bytes(), [0]); // empty state vector
    expect(reader.remaining, 0);
  });

  test('带文档名连接先认证，收到认证成功后再发送同步帧', () async {
    final channel = _FakeChannel();
    final realtime = DocumentRealtime(
        serverUrl: 'https://chat.example.com/base',
        token: 'mobile-session',
        documentId: 'doc-1',
        connector: (uri, token) {
          expect(uri.toString(),
              'wss://chat.example.com/base/api/client/document/collaboration');
          expect(token, 'mobile-session');
          return channel;
        });

    await realtime.connect();

    expect(channel.sent, hasLength(1));
    final auth = _FrameReader(channel.sent[0] as Uint8List);
    expect(auth.string(), 'doc-1');
    expect(auth.varUint(), HocuspocusMessageType.auth);
    expect(auth.varUint(), 0);
    expect(auth.string(), 'session-cookie');
    channel.emit(encodeHocuspocusAuthenticatedFrame(documentName: 'doc-1'));
    await Future<void>.delayed(Duration.zero);
    expect(channel.sent, hasLength(2));
    expect(_FrameReader(channel.sent[1] as Uint8List).string(), 'doc-1');
    await realtime.close();
  });
}

class _FrameReader {
  _FrameReader(Uint8List frame) : _frame = frame;
  final Uint8List _frame;
  int _offset = 0;

  int get remaining => _frame.length - _offset;

  int varUint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = _frame[_offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return value;
      shift += 7;
    }
  }

  Uint8List bytes() {
    final length = varUint();
    final value = Uint8List.sublistView(_frame, _offset, _offset + length);
    _offset += length;
    return value;
  }

  String string() {
    final value = bytes();
    return utf8.decode(value);
  }
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
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
