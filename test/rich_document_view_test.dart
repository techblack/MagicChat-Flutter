import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/features/projects/rich_document_view.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

void main() {
  testWidgets('渲染富文档 XML block、列表、任务、表格、图片和 marks', (tester) async {
    final document = yjs.Doc(yjs.DocOpts(guid: 'rich-view-test'));
    final body = document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _addHeading(body, '发布计划');
    _addParagraph(body, '这是加粗文字', marks: {'bold': true});
    final aligned = yjs.YXmlElement('paragraph')
      ..setAttribute('textAlign', 'right');
    aligned.insert(0, [yjs.YXmlText()..insert(0, '右对齐文本')]);
    body.insert(body.length, [aligned]);
    _addList(body, ordered: false, items: ['准备素材', '安排发布']);
    _addTaskList(body);
    _addTable(body);
    final image = yjs.YXmlElement('documentImage')
      ..setAttribute('fileId', 'file-1')
      ..setAttribute('alt', '产品截图');
    body.insert(body.length, [image]);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RichDocumentView(body: body))));

    expect(find.text('发布计划'), findsOneWidget);
    expect(find.text('准备素材'), findsOneWidget);
    expect(find.text('安排发布'), findsOneWidget);
    expect(tester.widget<Text>(find.text('右对齐文本')).textAlign, TextAlign.right);
    expect(find.text('需要确认'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('产品截图'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/rich_document_view.png'));
    document.destroy();
  });

  testWidgets('长按富文档文本块触发编辑回调', (tester) async {
    final document = yjs.Doc(yjs.DocOpts(guid: 'rich-edit-view-test'));
    final body = document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _addParagraph(body, '可编辑正文');
    yjs.YXmlText? edited;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentView(
                body: body, onEditText: (node) => edited = node))));

    await tester.longPress(find.text('可编辑正文'));
    expect(edited?.toString(), '可编辑正文');
    document.destroy();
  });

  testWidgets('点击富文档文本块切换为原位输入并回调内容', (tester) async {
    final document = yjs.Doc(yjs.DocOpts(guid: 'rich-inline-edit-test'));
    final body = document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _addParagraph(body, '原位正文');
    yjs.YXmlText? selected;
    String? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return RichDocumentView(
            body: body,
            selectedText: selected,
            onSelectText: (node) => setState(() => selected = node),
            onTextChanged: (node, value) => changed = value,
          );
        }),
      ),
    ));

    await tester.tap(find.text('原位正文'));
    await tester.pump();
    expect(find.byKey(const ValueKey('rich-document-inline-editor')),
        findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '新的正文');
    await tester.pump();
    expect(changed, '新的正文');
    document.destroy();
  });
}

void _addHeading(yjs.YXmlFragment body, String value) {
  final heading = yjs.YXmlElement('heading')..setAttribute('level', 1);
  final text = yjs.YXmlText()..insert(0, value);
  heading.insert(0, [text]);
  body.insert(body.length, [heading]);
}

void _addParagraph(yjs.YXmlFragment body, String value,
    {Map<String, Object?>? marks}) {
  final paragraph = yjs.YXmlElement('paragraph');
  final text = yjs.YXmlText()..insert(0, value, marks);
  paragraph.insert(0, [text]);
  body.insert(body.length, [paragraph]);
}

void _addList(yjs.YXmlFragment body,
    {required bool ordered, required List<String> items}) {
  final list = yjs.YXmlElement(ordered ? 'orderedList' : 'bulletList');
  for (final value in items) {
    final item = yjs.YXmlElement('listItem');
    final paragraph = yjs.YXmlElement('paragraph');
    paragraph.insert(0, [yjs.YXmlText()..insert(0, value)]);
    item.insert(0, [paragraph]);
    list.insert(list.length, [item]);
  }
  body.insert(body.length, [list]);
}

void _addTaskList(yjs.YXmlFragment body) {
  final list = yjs.YXmlElement('taskList');
  final item = yjs.YXmlElement('taskItem')..setAttribute('checked', true);
  final paragraph = yjs.YXmlElement('paragraph');
  paragraph.insert(0, [yjs.YXmlText()..insert(0, '需要确认')]);
  item.insert(0, [paragraph]);
  list.insert(0, [item]);
  body.insert(body.length, [list]);
}

void _addTable(yjs.YXmlFragment body) {
  final table = yjs.YXmlElement('table');
  final row = yjs.YXmlElement('tableRow');
  for (final value in ['负责人', '状态']) {
    final cell = yjs.YXmlElement('tableHeader');
    final paragraph = yjs.YXmlElement('paragraph');
    paragraph.insert(0, [yjs.YXmlText()..insert(0, value)]);
    cell.insert(0, [paragraph]);
    row.insert(row.length, [cell]);
  }
  table.insert(0, [row]);
  body.insert(body.length, [table]);
}
