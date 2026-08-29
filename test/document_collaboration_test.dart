import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_collaboration.dart';
import 'package:magicchat_client/data/document_realtime.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('Markdown 会话应用远端状态并发送本地 Yjs 更新', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-1',
        documentType: 'markdown',
        connector: (_, __) => channel);
    var notifications = 0;
    session.addListener(() => notifications++);

    await session.connect();
    expect(session.status, DocumentCollaborationStatus.connecting);
    expect(channel.sent, hasLength(1));
    session.replaceText('连接前不写入');
    expect(session.text, isEmpty);
    expect(channel.sent, hasLength(1));

    channel.emit(encodeHocuspocusAuthenticatedFrame(documentName: 'doc-1'));
    await Future<void>.delayed(Duration.zero);
    expect(channel.sent, hasLength(2));

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-1'));
    serverDocument.getText('markdown')!.insert(0, '# 远端正文');
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-1');
    yjs.writeVarUint(incoming, 0);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);

    expect(session.status, DocumentCollaborationStatus.synced);
    expect(session.text, '# 远端正文');
    final syncedNotifications = notifications;

    Uint8List? remoteUpdate;
    serverDocument.on('update', (update, [_, __, ___]) {
      remoteUpdate = update as Uint8List;
    });
    serverDocument.getText('markdown')!.insert(0, '前缀 ');
    final remoteFrame = yjs.createEncoder();
    yjs.writeVarString(remoteFrame, 'doc-1');
    yjs.writeVarUint(remoteFrame, 0);
    yjs.writeUpdate(remoteFrame, remoteUpdate!);
    channel.emit(yjs.toUint8Array(remoteFrame));
    await Future<void>.delayed(Duration.zero);

    expect(session.text, '前缀 # 远端正文');
    expect(notifications, greaterThan(syncedNotifications));

    session.replaceText('# 本地正文');
    expect(session.text, '# 本地正文');
    expect(channel.sent, hasLength(3));
    final updateDecoder = yjs.createDecoder(channel.sent.last as Uint8List);
    expect(yjs.readVarString(updateDecoder), 'doc-1');
    expect(yjs.readVarUint(updateDecoder), 0);
    yjs.readSyncMessage(
        updateDecoder, yjs.createEncoder(), serverDocument, 'server');
    expect(serverDocument.getText('markdown')!.toString(), '# 本地正文');

    session.replaceText('# 本地正文（已更新）');
    expect(session.text, '# 本地正文（已更新）');
    expect(channel.sent, hasLength(4));
    final secondUpdate = yjs.createDecoder(channel.sent.last as Uint8List);
    yjs.readVarString(secondUpdate);
    yjs.readVarUint(secondUpdate);
    yjs.readSyncMessage(
        secondUpdate, yjs.createEncoder(), serverDocument, 'server');
    expect(serverDocument.getText('markdown')!.toString(), '# 本地正文（已更新）');

    await session.close();
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
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
