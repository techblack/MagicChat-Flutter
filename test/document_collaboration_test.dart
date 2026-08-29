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
    session.setPresence({
      'user': {'name': '本地用户'}
    });
    expect(session.text, isEmpty);
    expect(channel.sent, hasLength(1));

    channel.emit(encodeHocuspocusAuthenticatedFrame(documentName: 'doc-1'));
    await Future<void>.delayed(Duration.zero);
    expect(channel.sent, hasLength(3));

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

    final remoteAwarenessDocument = yjs.Doc(yjs.DocOpts(guid: 'remote'));
    final remoteAwareness = yjs.Awareness(remoteAwarenessDocument);
    remoteAwareness.setLocalState({
      'user': {'name': '远端用户'}
    });
    final awarenessFrame = yjs.createEncoder();
    yjs.writeVarString(awarenessFrame, 'doc-1');
    yjs.writeVarUint(awarenessFrame, HocuspocusMessageType.awareness);
    yjs.writeVarUint8Array(awarenessFrame,
        yjs.encodeAwarenessUpdate(remoteAwareness, [remoteAwareness.clientID]));
    channel.emit(yjs.toUint8Array(awarenessFrame));
    await Future<void>.delayed(Duration.zero);

    expect(session.collaboratorCount, 1);
    expect(
        session.awarenessStates.values
            .where((state) => (state['user'] as Map?)?['name'] == '远端用户')
            .single['user'],
        {'name': '远端用户'});
    remoteAwarenessDocument.destroy();

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
    expect(channel.sent, hasLength(4));
    final updateDecoder = yjs.createDecoder(channel.sent.last as Uint8List);
    expect(yjs.readVarString(updateDecoder), 'doc-1');
    expect(yjs.readVarUint(updateDecoder), 0);
    yjs.readSyncMessage(
        updateDecoder, yjs.createEncoder(), serverDocument, 'server');
    expect(serverDocument.getText('markdown')!.toString(), '# 本地正文');

    session.replaceText('# 本地正文（已更新）');
    expect(session.text, '# 本地正文（已更新）');
    expect(channel.sent, hasLength(5));
    final secondUpdate = yjs.createDecoder(channel.sent.last as Uint8List);
    yjs.readVarString(secondUpdate);
    yjs.readVarUint(secondUpdate);
    yjs.readSyncMessage(
        secondUpdate, yjs.createEncoder(), serverDocument, 'server');
    expect(serverDocument.getText('markdown')!.toString(), '# 本地正文（已更新）');

    await session.close();
  });

  test('富文档会话绑定 Y.XmlFragment("body") 并同步持久化正文', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-rich-1',
        documentType: 'document',
        connector: (_, __) => channel);

    expect(session.body, isA<yjs.YXmlFragment>());
    expect(session.text, isEmpty);
    await session.connect();
    expect(session.status, DocumentCollaborationStatus.connecting);
    expect(channel.sent, hasLength(1));

    channel
        .emit(encodeHocuspocusAuthenticatedFrame(documentName: 'doc-rich-1'));
    await Future<void>.delayed(Duration.zero);

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-rich-1'));
    final serverBody =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _insertParagraphs(serverBody, '富文档正文\n第二段');
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-rich-1');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);

    expect(session.status, DocumentCollaborationStatus.synced);
    expect(session.text, '富文档正文\n第二段');

    session.replaceText('本地富文档正文');
    expect(session.text, '本地富文档正文');
    expect(channel.sent, hasLength(4));
    final update = yjs.createDecoder(channel.sent.last as Uint8List);
    expect(yjs.readVarString(update), 'doc-rich-1');
    expect(yjs.readVarUint(update), HocuspocusMessageType.sync);
    yjs.readSyncMessage(update, yjs.createEncoder(), serverDocument, 'server');
    expect(_xmlText(serverBody), '本地富文档正文');

    await session.close();
    serverDocument.destroy();
  });
}

void _insertParagraphs(yjs.YXmlFragment body, String value) {
  for (final line in value.split('\n')) {
    final paragraph = yjs.YXmlElement('paragraph');
    body.insert(body.length, [paragraph]);
    if (line.isEmpty) continue;
    final content = yjs.YXmlText();
    paragraph.insert(0, [content]);
    content.insert(0, line);
  }
}

String _xmlText(yjs.YXmlFragment body) => body.toArray().map((node) {
      if (node is yjs.YXmlFragment) {
        return node
            .toArray()
            .whereType<yjs.YText>()
            .map((text) => text.toString())
            .join();
      }
      return '';
    }).join('\n');

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
