import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_collaboration.dart';
import 'package:magicchat_client/data/document_realtime.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

void main() {
  test('水平分割线使用官方属性并支持更新、删除和撤销', () async {
    final fixture = await _syncedSession('horizontal-rule');
    addTearDown(fixture.close);
    final paragraph = _textBlock('paragraph', '正文');
    fixture.session.body.insert(0, [paragraph.block]);

    final rule = fixture.session.insertHorizontalRule(near: paragraph.text);

    expect(rule, isNotNull);
    expect(fixture.session.body.toArray(), [paragraph.block, rule]);
    expect(
      fixture.session.horizontalRuleAttributes(rule!),
      const (lineStyle: 'solid', thickness: 1),
    );
    expect(
      fixture.session.updateHorizontalRule(
        rule,
        const (lineStyle: 'dashed', thickness: 4),
      ),
      isTrue,
    );
    expect(
      fixture.session.horizontalRuleAttributes(rule),
      const (lineStyle: 'dashed', thickness: 4),
    );
    expect(fixture.session.undo(), isTrue);
    expect(
      fixture.session.horizontalRuleAttributes(rule),
      const (lineStyle: 'solid', thickness: 1),
    );
    expect(fixture.session.redo(), isTrue);
    expect(fixture.session.horizontalRuleAttributes(rule).thickness, 4);
    expect(fixture.session.deleteHorizontalRule(rule), isTrue);
    expect(fixture.session.body.toArray(), [paragraph.block]);
    expect(fixture.session.undo(), isTrue);
    expect(
      fixture.session.body
          .toArray()
          .whereType<yjs.YXmlElement>()
          .where((element) => element.name == 'horizontalRule'),
      hasLength(1),
    );
  });

  test('列表结构转换保留全部项目、marks、背景和任务状态', () async {
    final fixture = await _syncedSession('list-transform');
    addTearDown(fixture.close);
    final list = yjs.YXmlElement('bulletList')
      ..setAttribute('blockBackgroundColor', 'oklch(93.6% 0.032 17.717)');
    final first = _listItem('第一项', marks: {'bold': true});
    final second = _listItem('第二项', marks: {'italic': true});
    list.insert(0, [first.item, second.item]);
    fixture.session.body.insert(0, [list]);
    first.text.delete(0, first.text.length);
    first.text.insert(0, '第一', {'bold': true});
    first.text.insert(first.text.length, '项');

    expect(fixture.session.xmlTextBlockType(first.text),
        RichDocumentBlockType.bulletList);
    final selected = fixture.session
        .transformXmlTextBlock(first.text, RichDocumentBlockType.taskList);

    expect(selected, isNotNull);
    var taskList =
        fixture.session.body.toArray().whereType<yjs.YXmlElement>().single;
    expect(taskList.name, 'taskList');
    expect(taskList.getAttribute('blockBackgroundColor'),
        'oklch(93.6% 0.032 17.717)');
    var tasks = taskList.toArray().whereType<yjs.YXmlElement>().toList();
    expect(tasks.map((item) => item.name), ['taskItem', 'taskItem']);
    expect(tasks.map((item) => item.getAttribute('checked')), [false, false]);
    var texts = tasks.map(_itemText).toList();
    expect(texts.map((text) => text.toString()), ['第一项', '第二项']);
    expect(texts.first.toDelta(), [
      {
        'insert': '第一',
        'attributes': {'bold': true},
      },
      {'insert': '项'},
    ]);
    expect(texts.last.toDelta().single['attributes'],
        containsPair('italic', true));
    expect(fixture.session.undo(), isTrue);
    expect((fixture.session.body.toArray().single as yjs.YXmlElement).name,
        'bulletList');
    expect(fixture.session.redo(), isTrue);
    taskList = fixture.session.body.toArray().single as yjs.YXmlElement;
    tasks = taskList.toArray().whereType<yjs.YXmlElement>().toList();
    texts = tasks.map(_itemText).toList();
    expect(taskList.name, 'taskList');

    expect(fixture.session.setTaskItemChecked(tasks.first, true), isTrue);
    expect(tasks.first.getAttribute('checked'), isTrue);
    expect(fixture.session.setTaskItemChecked(tasks.first, true), isFalse);
    expect(fixture.session.undo(), isTrue);
    expect(tasks.first.getAttribute('checked'), isFalse);
    expect(fixture.session.redo(), isTrue);
    expect(tasks.first.getAttribute('checked'), isTrue);

    final quote = fixture.session
        .transformXmlTextBlock(texts.first, RichDocumentBlockType.blockquote);
    expect(quote, isNotNull);
    final blockquote =
        fixture.session.body.toArray().whereType<yjs.YXmlElement>().single;
    expect(blockquote.name, 'blockquote');
    expect(
        _textLeaves(blockquote).map((text) => text.toString()), ['第一项', '第二项']);

    final code = fixture.session
        .transformXmlTextBlock(quote!, RichDocumentBlockType.codeBlock);
    expect(code, isNotNull);
    final codeBlocks =
        fixture.session.body.toArray().whereType<yjs.YXmlElement>().toList();
    expect(codeBlocks.map((block) => block.name), ['codeBlock', 'codeBlock']);
    expect(_textLeaves(fixture.session.body).map((text) => text.toString()),
        ['第一项', '第二项']);
    expect(code!.toDelta().single['attributes'], isNull);
  });

  test('表格单元格的转换、插入和删除保持在当前单元格内', () async {
    final fixture = await _syncedSession('table-cell-transform');
    addTearDown(fixture.close);
    final table = yjs.YXmlElement('table');
    final row = yjs.YXmlElement('tableRow');
    final cell = yjs.YXmlElement('tableCell');
    final paragraph = _textBlock('paragraph', '单元格');
    cell.insert(0, [paragraph.block]);
    row.insert(0, [cell]);
    table.insert(0, [row]);
    fixture.session.body.insert(0, [table]);

    expect(fixture.session.xmlTextBlockType(paragraph.text),
        RichDocumentBlockType.paragraph);
    final rule = fixture.session.insertHorizontalRule(near: paragraph.text);
    expect(rule, isNotNull);
    expect(cell.toArray().whereType<yjs.YXmlElement>().map((item) => item.name),
        ['paragraph', 'horizontalRule']);
    expect(fixture.session.deleteHorizontalRule(rule!), isTrue);
    final quote = fixture.session.transformXmlTextBlock(
        paragraph.text, RichDocumentBlockType.blockquote);

    expect(quote, isNotNull);
    expect(fixture.session.body.toArray(), [table]);
    expect(
        cell.toArray().whereType<yjs.YXmlElement>().single.name, 'blockquote');
    final inserted = fixture.session.insertParagraphNear(quote!, after: true);
    expect(inserted, isNotNull);
    expect(cell.toArray().whereType<yjs.YXmlElement>().map((item) => item.name),
        ['blockquote', 'paragraph']);
    fixture.session.replaceXmlText(inserted!, '下一行');
    expect(fixture.session.deleteXmlTextBlock(quote), isNull);
    expect(
        cell.toArray().whereType<yjs.YXmlElement>().single.name, 'paragraph');
    expect(_textLeaves(table).single.toString(), '下一行');
  });

  test('包含未知嵌套节点的结构不会被转换或重写', () async {
    final fixture = await _syncedSession('unknown-structure');
    addTearDown(fixture.close);
    final list = yjs.YXmlElement('bulletList');
    final item = _listItem('已知内容');
    final unknown = yjs.YXmlElement('customWidget')
      ..setAttribute('data', 'preserve');
    list.insert(0, [item.item]);
    fixture.session.body.insert(0, [list]);
    item.item.insert(item.item.length, [unknown]);

    expect(fixture.session.xmlTextBlockType(item.text), isNull);
    expect(
      fixture.session
          .transformXmlTextBlock(item.text, RichDocumentBlockType.paragraph),
      isNull,
    );
    expect(fixture.session.body.toArray().single, same(list));
    expect(item.item.toArray().last, same(unknown));
    expect(unknown.getAttribute('data'), 'preserve');
  });
}

({yjs.YXmlElement block, yjs.YXmlText text}) _textBlock(
    String name, String value,
    {Map<String, Object?>? marks}) {
  final block = yjs.YXmlElement(name);
  final text = yjs.YXmlText()..insert(0, value, marks);
  block.insert(0, [text]);
  return (block: block, text: text);
}

({yjs.YXmlElement item, yjs.YXmlText text}) _listItem(String value,
    {Map<String, Object?>? marks}) {
  final item = yjs.YXmlElement('listItem');
  final block = _textBlock('paragraph', value, marks: marks);
  item.insert(0, [block.block]);
  return (item: item, text: block.text);
}

yjs.YXmlText _itemText(yjs.YXmlElement item) => item
    .toArray()
    .whereType<yjs.YXmlElement>()
    .single
    .toArray()
    .whereType<yjs.YXmlText>()
    .single;

List<yjs.YXmlText> _textLeaves(yjs.YXmlFragment parent) {
  final result = <yjs.YXmlText>[];
  for (final child in parent.toArray()) {
    if (child is yjs.YXmlText) {
      result.add(child);
    } else if (child is yjs.YXmlFragment) {
      result.addAll(_textLeaves(child));
    }
  }
  return result;
}

Future<_SessionFixture> _syncedSession(String id) async {
  final channel = _FakeChannel();
  final session = DocumentCollaborationSession(
    serverUrl: 'https://chat.example.com',
    token: 'session-token',
    documentId: id,
    documentType: 'document',
    connector: (_, __) => channel,
  );
  await session.connect();
  channel.emit(encodeHocuspocusAuthenticatedFrame(documentName: id));
  await Future<void>.delayed(Duration.zero);
  final serverDocument = yjs.Doc(yjs.DocOpts(guid: id));
  final sync = yjs.createEncoder();
  yjs.writeVarString(sync, id);
  yjs.writeVarUint(sync, HocuspocusMessageType.sync);
  yjs.writeSyncStep2(sync, serverDocument);
  channel.emit(yjs.toUint8Array(sync));
  await Future<void>.delayed(Duration.zero);
  expect(session.status, DocumentCollaborationStatus.synced);
  return _SessionFixture(session, serverDocument);
}

class _SessionFixture {
  const _SessionFixture(this.session, this.serverDocument);

  final DocumentCollaborationSession session;
  final yjs.Doc serverDocument;

  Future<void> close() async {
    await session.close();
    serverDocument.destroy();
  }
}

class _FakeChannel implements WebSocketChannel {
  final _incoming = StreamController<Object?>();
  late final WebSocketSink _sink = _FakeSink();

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
  @override
  void add(Object? data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> close([int? code, String? reason]) async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
