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

  test('富文档只追加 XML block，不改写已有 marks', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-rich-append',
        documentType: 'document',
        connector: (_, __) => channel);
    await session.connect();
    channel.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'doc-rich-append'));
    await Future<void>.delayed(Duration.zero);

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-rich-append'));
    final serverBody =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    final original = yjs.YXmlElement('paragraph');
    final originalText = yjs.YXmlText()..insert(0, '保留加粗', {'bold': true});
    original.insert(0, [originalText]);
    serverBody.insert(0, [original]);
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-rich-append');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);
    expect(session.status, DocumentCollaborationStatus.synced);

    final sentBeforeAppend = channel.sent.length;
    expect(
        session.appendTextBlock('新增二级标题', type: RichDocumentBlockType.heading2),
        isTrue);
    expect(channel.sent, hasLength(sentBeforeAppend + 1));
    final update = yjs.createDecoder(channel.sent.last as Uint8List);
    expect(yjs.readVarString(update), 'doc-rich-append');
    expect(yjs.readVarUint(update), HocuspocusMessageType.sync);
    yjs.readSyncMessage(update, yjs.createEncoder(), serverDocument, 'server');

    final blocks = serverBody.toArray().whereType<yjs.YXmlElement>().toList();
    expect(blocks, hasLength(2));
    expect(blocks.first.name, 'paragraph');
    expect(blocks.last.name, 'heading');
    expect(blocks.last.getAttribute('level'), 2);
    expect(blocks.last.toArray().whereType<yjs.YXmlText>().single.toString(),
        '新增二级标题');
    final attributes = blocks.first
        .toArray()
        .whereType<yjs.YXmlText>()
        .single
        .toDelta()
        .single['attributes'];
    expect(attributes, containsPair('bold', true));

    expect(
        session.appendTextBlock('引用内容', type: RichDocumentBlockType.blockquote),
        isTrue);
    final blockquoteUpdate = yjs.createDecoder(channel.sent.last as Uint8List);
    expect(yjs.readVarString(blockquoteUpdate), 'doc-rich-append');
    expect(yjs.readVarUint(blockquoteUpdate), HocuspocusMessageType.sync);
    yjs.readSyncMessage(
        blockquoteUpdate, yjs.createEncoder(), serverDocument, 'server');
    final blockquote = serverBody.toArray().whereType<yjs.YXmlElement>().last;
    expect(blockquote.name, 'blockquote');
    final quoteParagraph =
        blockquote.toArray().whereType<yjs.YXmlElement>().single;
    expect(quoteParagraph.name, 'paragraph');
    expect(quoteParagraph.toArray().whereType<yjs.YXmlText>().single.toString(),
        '引用内容');
    await session.close();
    serverDocument.destroy();
  });

  test('富文档可编辑已有文本块并同步到协作状态', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-text-edit',
        documentType: 'document',
        connector: (_, __) => channel);
    await session.connect();
    channel.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'doc-text-edit'));
    await Future<void>.delayed(Duration.zero);

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-text-edit'));
    final serverBody =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _insertParagraphs(serverBody, '原始正文');
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-text-edit');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);
    expect(session.status, DocumentCollaborationStatus.synced);

    final paragraph =
        session.body.toArray().whereType<yjs.YXmlElement>().single;
    final text = paragraph.toArray().whereType<yjs.YXmlText>().single;
    final sentBeforeEdit = channel.sent.length;
    var notifications = 0;
    session.addListener(() => notifications++);
    session.replaceXmlText(text, '编辑后的正文');
    expect(channel.sent, hasLength(sentBeforeEdit + 1));
    expect(notifications, 1);
    final update = yjs.createDecoder(channel.sent.last as Uint8List);
    expect(yjs.readVarString(update), 'doc-text-edit');
    expect(yjs.readVarUint(update), HocuspocusMessageType.sync);
    yjs.readSyncMessage(update, yjs.createEncoder(), serverDocument, 'server');
    expect(_xmlText(serverBody), '编辑后的正文');

    final markedParagraph = yjs.YXmlElement('paragraph');
    final markedText = yjs.YXmlText()..insert(0, '带标记正文', {'bold': true});
    markedParagraph.insert(0, [markedText]);
    session.body.insert(session.body.length, [markedParagraph]);
    session.replaceXmlText(markedText, '编辑后的加粗正文');
    expect(
        markedText.toDelta().single['attributes'], containsPair('bold', true));

    final markedUpdateCount = channel.sent.length;
    session.replaceXmlText(markedText, '编辑后的加粗正文', marks: const {});
    expect(channel.sent, hasLength(markedUpdateCount + 1));
    expect(markedText.toDelta().single['attributes'], isNull);

    await session.close();
    serverDocument.destroy();
  });

  test('协作会话断线后重连并保留当前文档状态', () async {
    final first = _FakeChannel();
    final second = _FakeChannel();
    final channels = [first, second];
    var connection = 0;
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-reconnect',
        documentType: 'markdown',
        connector: (_, __) => channels[connection++]);

    await session.connect();
    first.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'doc-reconnect'));
    await Future<void>.delayed(Duration.zero);
    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-reconnect'));
    serverDocument.getText('markdown')!.insert(0, '重连前正文');
    final initial = yjs.createEncoder();
    yjs.writeVarString(initial, 'doc-reconnect');
    yjs.writeVarUint(initial, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(initial, serverDocument);
    first.emit(yjs.toUint8Array(initial));
    await Future<void>.delayed(Duration.zero);
    expect(session.status, DocumentCollaborationStatus.synced);

    await session.reconnect();
    expect(session.status, DocumentCollaborationStatus.connecting);
    expect(second.sent, hasLength(1));
    second.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'doc-reconnect'));
    await Future<void>.delayed(Duration.zero);
    final resync = yjs.createEncoder();
    yjs.writeVarString(resync, 'doc-reconnect');
    yjs.writeVarUint(resync, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(resync, serverDocument);
    second.emit(yjs.toUint8Array(resync));
    await Future<void>.delayed(Duration.zero);

    expect(session.status, DocumentCollaborationStatus.synced);
    expect(session.text, '重连前正文');
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
