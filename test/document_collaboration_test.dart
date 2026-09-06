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

  test('富文档块背景通过 Yjs 往返并拒绝未知色值', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-block-background',
        documentType: 'document',
        connector: (_, __) => channel);
    await session.connect();
    channel.emit(encodeHocuspocusAuthenticatedFrame(
        documentName: 'doc-block-background'));
    await Future<void>.delayed(Duration.zero);

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-block-background'));
    final serverBody =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _insertParagraphs(serverBody, '背景正文');
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-block-background');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);

    final text = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .single
        .toArray()
        .whereType<yjs.YXmlText>()
        .single;
    const background = 'oklch(93.6% 0.032 17.717)';
    expect(session.setXmlTextBlockBackground(text, background), isTrue);
    _applySyncUpdate(channel.sent.last as Uint8List, serverDocument);
    expect(
        serverBody
            .toArray()
            .whereType<yjs.YXmlElement>()
            .single
            .getAttribute('blockBackgroundColor'),
        background);

    final sentBeforeInvalid = channel.sent.length;
    expect(session.setXmlTextBlockBackground(text, 'red; position: fixed'),
        isFalse);
    expect(channel.sent, hasLength(sentBeforeInvalid));
    expect(session.setXmlTextBlockBackground(text, null), isTrue);
    _applySyncUpdate(channel.sent.last as Uint8List, serverDocument);
    expect(
        serverBody
            .toArray()
            .whereType<yjs.YXmlElement>()
            .single
            .getAttribute('blockBackgroundColor'),
        isNull);

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
    expect(session.canUndo, isFalse, reason: '远端同步不能进入本机撤销历史');
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
    expect(session.canUndo, isTrue);
    expect(session.undo(), isTrue);
    expect(session.text, '原始正文');
    expect(session.canRedo, isTrue);
    expect(session.redo(), isTrue);
    expect(session.text, '编辑后的正文');

    final markedParagraph = yjs.YXmlElement('paragraph');
    final markedText = yjs.YXmlText()..insert(0, '带标记正文', {'bold': true});
    markedParagraph.insert(0, [markedText]);
    session.body.insert(session.body.length, [markedParagraph]);
    session.replaceXmlText(markedText, '编辑后的加粗正文');
    expect(
        markedText.toDelta().every((operation) {
          final attributes = operation['attributes'];
          return attributes is Map && attributes['bold'] == true;
        }),
        isTrue);

    final markedUpdateCount = channel.sent.length;
    session.replaceXmlText(markedText, '编辑后的加粗正文', marks: const {});
    expect(channel.sent, hasLength(markedUpdateCount + 1));
    expect(
        markedText.toDelta().every((operation) {
          final attributes = operation['attributes'];
          return attributes == null ||
              (attributes is Map && attributes.isEmpty);
        }),
        isTrue);
    expect(session.xmlTextAlignment(markedText), 'left');
    expect(session.setXmlTextAlignment(markedText, 'center'), isTrue);
    expect(markedParagraph.getAttribute('textAlign'), 'center');
    const background = 'oklch(93.6% 0.032 17.717)';
    expect(session.setXmlTextBlockBackground(markedText, background), isTrue);
    expect(markedParagraph.getAttribute('blockBackgroundColor'), background);
    expect(session.xmlTextBlockBackground(markedText), background);
    expect(
        session.setXmlTextBlockBackground(markedText, 'red; position: fixed'),
        isFalse);
    expect(markedParagraph.getAttribute('blockBackgroundColor'), background);

    final heading = session.transformXmlTextBlock(
        markedText, RichDocumentBlockType.heading1);
    expect(heading, isNotNull);
    expect(session.xmlTextBlockType(heading!), RichDocumentBlockType.heading1);
    final headingBlock = heading.parent! as yjs.YXmlElement;
    expect(headingBlock.name, 'heading');
    expect(headingBlock.getAttribute('level'), 1);
    expect(headingBlock.getAttribute('textAlign'), 'center');
    expect(headingBlock.getAttribute('blockBackgroundColor'), background);
    expect(heading.toString(), '编辑后的加粗正文');
    expect(session.setXmlTextAlignment(heading, 'left'), isTrue);
    expect(headingBlock.getAttribute('textAlign'), isNull);
    expect(session.setXmlTextBlockBackground(heading, null), isTrue);
    expect(headingBlock.getAttribute('blockBackgroundColor'), isNull);

    final before = session.insertParagraphNear(heading, after: false);
    final after = session.insertParagraphNear(heading, after: true);
    expect(before, isNotNull);
    expect(after, isNotNull);
    session.replaceXmlText(before!, '上方段落');
    session.replaceXmlText(after!, '下方段落');
    expect(session.text, contains('上方段落'));
    expect(session.text, contains('下方段落'));

    expect(session.deleteXmlTextBlock(heading), isNull);
    expect(session.text, isNot(contains('编辑后的加粗正文')));

    final firstCell = session.insertTable(near: before, rows: 2, columns: 3);
    expect(firstCell, isNotNull);
    final table = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((element) => element.name == 'table')
        .single;
    final rows = table.toArray().whereType<yjs.YXmlElement>().toList();
    expect(rows, hasLength(2));
    expect(
        rows.first
            .toArray()
            .whereType<yjs.YXmlElement>()
            .map((cell) => cell.name),
        ['tableHeader', 'tableHeader', 'tableHeader']);
    expect(
        rows.last
            .toArray()
            .whereType<yjs.YXmlElement>()
            .map((cell) => cell.name),
        ['tableCell', 'tableCell', 'tableCell']);
    expect(session.undo(), isTrue);
    expect(
        session.body
            .toArray()
            .whereType<yjs.YXmlElement>()
            .where((element) => element.name == 'table'),
        isEmpty);
    expect(session.redo(), isTrue);
    expect(
        session.body
            .toArray()
            .whereType<yjs.YXmlElement>()
            .where((element) => element.name == 'table'),
        hasLength(1));

    final image = session.insertDocumentImage(near: before);
    expect(image, isNotNull);
    expect(session.documentImageAttributes(image!), const (
      alignment: 'center',
      alt: '',
      externalUrl: null,
      fileId: null,
      width: 100,
    ));
    expect(
        session.updateDocumentImage(image, const (
          alignment: 'right',
          alt: '架构图',
          externalUrl: 'https://example.com/diagram.png',
          fileId: null,
          width: 63,
        )),
        isTrue);
    expect(session.documentImageAttributes(image), const (
      alignment: 'right',
      alt: '架构图',
      externalUrl: 'https://example.com/diagram.png',
      fileId: null,
      width: 65,
    ));
    expect(session.undo(), isTrue);
    expect(session.documentImageAttributes(image).externalUrl, isNull);
    expect(session.redo(), isTrue);
    expect(session.documentImageAttributes(image).alt, '架构图');
    expect(session.deleteDocumentImage(image), isTrue);
    expect(session.body.toArray().contains(image), isFalse);
    expect(session.undo(), isTrue);
    expect(
        session.body
            .toArray()
            .whereType<yjs.YXmlElement>()
            .where((element) => element.name == 'documentImage'),
        hasLength(1));

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

  test('标准富文档表格支持安全增删行列、删除整表和撤销重做', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-table-structure',
        documentType: 'document',
        connector: (_, __) => channel);
    await session.connect();
    channel.emit(encodeHocuspocusAuthenticatedFrame(
        documentName: 'doc-table-structure'));
    await Future<void>.delayed(Duration.zero);
    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-table-structure'));
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-table-structure');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);

    final first = session.insertTable(rows: 2, columns: 2)!;
    final table = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((element) => element.name == 'table')
        .single;
    final originalCell = _tableCells(_tableRows(table).first).first;
    final unknown = yjs.YXmlElement('customCellBlock');
    final unknownText = yjs.YXmlText()..insert(0, '保留未知内容');
    unknown.insert(0, [unknownText]);
    originalCell.insert(originalCell.length, [unknown]);
    expect(session.isXmlTextInEditableTable(first), isTrue);

    var result = session.editTable(first, RichDocumentTableAction.addRowAfter);
    expect(result.changed, isTrue);
    expect(_tableRows(table), hasLength(3));
    expect(_tableCells(_tableRows(table)[1]).map((cell) => cell.name),
        ['tableHeader', 'tableHeader']);

    result = session.editTable(
        result.selection!, RichDocumentTableAction.addRowBefore);
    expect(_tableRows(table), hasLength(4));
    result = session.editTable(
        result.selection!, RichDocumentTableAction.addColumnAfter);
    expect(_tableRows(table).map((row) => _tableCells(row).length),
        everyElement(3));
    result = session.editTable(
        result.selection!, RichDocumentTableAction.addColumnBefore);
    expect(_tableRows(table).map((row) => _tableCells(row).length),
        everyElement(4));
    expect(identical(unknown.parent, originalCell), isTrue);
    expect(unknownText.toString(), '保留未知内容');

    result =
        session.editTable(result.selection!, RichDocumentTableAction.deleteRow);
    expect(_tableRows(table), hasLength(3));
    result = session.editTable(
        result.selection!, RichDocumentTableAction.deleteColumn);
    expect(_tableRows(table).map((row) => _tableCells(row).length),
        everyElement(3));
    expect(session.undo(), isTrue);
    expect(_tableRows(table).map((row) => _tableCells(row).length),
        everyElement(4));
    expect(session.redo(), isTrue);
    expect(_tableRows(table).map((row) => _tableCells(row).length),
        everyElement(3));

    result = session.editTable(
        result.selection!, RichDocumentTableAction.deleteTable);
    expect(result.changed, isTrue);
    expect(
        session.body.toArray().whereType<yjs.YXmlElement>().map((e) => e.name),
        ['paragraph']);
    expect(result.selection, isNotNull);
    expect(session.undo(), isTrue);
    final restoredTable = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((element) => element.name == 'table')
        .single;
    expect(_tableRows(restoredTable), hasLength(3));
    final restoredCell = _tableCells(_tableRows(restoredTable).first).first;
    final restoredParagraph = restoredCell
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((element) => element.name == 'paragraph')
        .first;
    final restoredFirst =
        restoredParagraph.toArray().whereType<yjs.YXmlText>().single;

    restoredCell.setAttribute('colspan', 2);
    expect(session.isXmlTextInEditableTable(restoredFirst), isFalse);
    expect(
        session
            .editTable(restoredFirst, RichDocumentTableAction.deleteColumn)
            .changed,
        isFalse);
    expect(_tableRows(restoredTable).map((row) => _tableCells(row).length),
        everyElement(3));

    restoredCell.removeAttribute('colspan');
    result =
        session.editTable(restoredFirst, RichDocumentTableAction.deleteTable);
    final onlyCell =
        session.insertTable(near: result.selection, rows: 1, columns: 1)!;
    result = session.editTable(onlyCell, RichDocumentTableAction.deleteColumn);
    expect(result.selection, isNotNull);
    expect(
        session.body.toArray().whereType<yjs.YXmlElement>().map((e) => e.name),
        ['paragraph']);
    expect(session.undo(), isTrue);
    final restoredOnlyTable = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((element) => element.name == 'table')
        .single;
    final restoredOnlyCell =
        _tableCells(_tableRows(restoredOnlyTable).single).single;
    final restoredOnlyParagraph = restoredOnlyCell
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((element) => element.name == 'paragraph')
        .single;
    final restoredOnlyText =
        restoredOnlyParagraph.toArray().whereType<yjs.YXmlText>().single;
    result =
        session.editTable(restoredOnlyText, RichDocumentTableAction.deleteRow);
    expect(result.selection, isNotNull);
    expect(
        session.body.toArray().whereType<yjs.YXmlElement>().map((e) => e.name),
        ['paragraph']);

    await session.close();
    serverDocument.destroy();
  });

  test('富文档粘贴原位插入标准块并保留已有未知节点', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-rich-paste',
        documentType: 'document',
        connector: (_, __) => channel);
    await session.connect();
    channel.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'doc-rich-paste'));
    await Future<void>.delayed(Duration.zero);
    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-rich-paste'));
    final serverBody =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    final paragraph = yjs.YXmlElement('paragraph');
    final selected = yjs.YXmlText()..insert(0, '已有正文');
    paragraph.insert(0, [selected]);
    final unknown = yjs.YXmlElement('futureBlock');
    unknown.insert(0, [yjs.YXmlText()..insert(0, '未知结构')]);
    serverBody.insert(0, [paragraph, unknown]);
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-rich-paste');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);

    final localBlocks =
        session.body.toArray().whereType<yjs.YXmlElement>().toList();
    final localParagraph = localBlocks.first;
    final localSelected =
        localParagraph.toArray().whereType<yjs.YXmlText>().single;
    final localUnknown = localBlocks.last;
    final result = session.pasteRichDocument(
        (html: '<h2>粘贴标题</h2><p><strong>粘贴正文</strong></p>', text: null),
        near: localSelected);

    expect(result.changed, isTrue);
    expect(result.selection?.toString(), '粘贴标题');
    final afterPaste =
        session.body.toArray().whereType<yjs.YXmlElement>().toList();
    expect(afterPaste.map((block) => block.name),
        ['paragraph', 'heading', 'paragraph', 'futureBlock']);
    expect(identical(afterPaste.last, localUnknown), isTrue);
    expect(localUnknown.toString(), contains('未知结构'));
    expect(session.undo(), isTrue);
    final afterUndo =
        session.body.toArray().whereType<yjs.YXmlElement>().toList();
    expect(afterUndo.map((block) => block.name), ['paragraph', 'futureBlock']);
    expect(afterUndo.first.toString(), contains('已有正文'));
    expect(afterUndo.last.toString(), contains('未知结构'));

    await session.close();
    serverDocument.destroy();
  });

  test('富文档区间 marks 按 UTF-16 边界分割并增量同步输入', () async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'doc-rich-range-format',
        documentType: 'document',
        connector: (_, __) => channel);
    await session.connect();
    channel.emit(encodeHocuspocusAuthenticatedFrame(
        documentName: 'doc-rich-range-format'));
    await Future<void>.delayed(Duration.zero);
    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'doc-rich-range-format'));
    final serverBody =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    final paragraph = yjs.YXmlElement('paragraph');
    final text = yjs.YXmlText()
      ..insert(0, 'A')
      ..insert(1, '😀B', {'bold': true})
      ..insert(4, 'C', {'italic': true});
    paragraph.insert(0, [text]);
    serverBody.insert(0, [paragraph]);
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'doc-rich-range-format');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await Future<void>.delayed(Duration.zero);
    final localText = (session.body.toArray().single as yjs.YXmlElement)
        .toArray()
        .whereType<yjs.YXmlText>()
        .single;
    final sentBefore = channel.sent.length;

    expect(localText.toString(), 'A😀BC');
    expect(localText.length, 5);
    expect(session.xmlTextMarksForRange(localText, 1, 3),
        containsPair('bold', true));
    expect(session.xmlTextMarksForRange(localText, 0, 4), isEmpty);
    expect(
        session.updateXmlTextMarks(localText, 1, 2, {'code': true}), isFalse);
    expect(localText.toString(), 'A😀BC');
    expect(session.updateXmlTextMarks(localText, 1, 3, {'underline': true}),
        isTrue);
    expect(localText.toString(), 'A😀BC');
    final emoji = localText
        .toDelta()
        .firstWhere((operation) => operation['insert'] == '😀');
    expect(emoji['attributes'], containsPair('bold', true));
    expect(emoji['attributes'], containsPair('underline', true));

    expect(
        session.updateXmlTextMarks(localText, 0, 1, {
          'bold': true,
          'italic': true,
          'underline': true,
          'strike': true,
          'code': true,
          'textStyle': {'color': '#2563eb'},
          'highlight': {'color': '#ca8a04'},
          'link': {'href': 'https://example.com'},
        }),
        isTrue);
    expect(session.xmlTextLinkRange(localText, 0), (start: 0, end: 1));
    expect(session.replaceXmlTextMarks(localText, 0, 1, const {}), isTrue);
    expect(session.xmlTextMarksForRange(localText, 0, 1), isEmpty);

    expect(
        session
            .replaceXmlTextPreservingMarks(localText, 'A😀XBC', {'code': true}),
        isTrue);
    expect(localText.toString(), 'A😀XBC');
    final inserted = localText
        .toDelta()
        .firstWhere((operation) => '${operation['insert']}'.contains('X'));
    expect(inserted['attributes'], containsPair('code', true));
    final boldRemainder = localText
        .toDelta()
        .firstWhere((operation) => '${operation['insert']}'.contains('B'));
    expect(boldRemainder['attributes'], containsPair('bold', true));
    expect(
        session
            .replaceXmlTextPreservingMarks(localText, 'A😀XC', {'code': true}),
        isTrue);
    expect(localText.toString(), 'A😀XC');
    expect(session.undo(), isTrue);
    expect(localText.toString(), 'A😀XBC');

    for (final update in channel.sent.skip(sentBefore).whereType<Uint8List>()) {
      _applySyncUpdate(update, serverDocument);
    }
    final roundTrip = (serverBody.toArray().single as yjs.YXmlElement)
        .toArray()
        .whereType<yjs.YXmlText>()
        .single;
    expect(roundTrip.toString(), localText.toString());
    expect(roundTrip.toDelta(), localText.toDelta());

    await session.close();
    serverDocument.destroy();
  });
}

List<yjs.YXmlElement> _tableRows(yjs.YXmlElement table) => table
    .toArray()
    .whereType<yjs.YXmlElement>()
    .where((row) => row.name == 'tableRow')
    .toList(growable: false);

List<yjs.YXmlElement> _tableCells(yjs.YXmlElement row) => row
    .toArray()
    .whereType<yjs.YXmlElement>()
    .where((cell) => cell.name == 'tableCell' || cell.name == 'tableHeader')
    .toList(growable: false);

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

void _applySyncUpdate(Uint8List update, yjs.Doc document) {
  final decoder = yjs.createDecoder(update);
  yjs.readVarString(decoder);
  yjs.readVarUint(decoder);
  yjs.readSyncMessage(decoder, yjs.createEncoder(), document, 'server');
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
