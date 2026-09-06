import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_collaboration.dart';
import 'package:magicchat_client/data/document_realtime.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/document_editor_page.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

void main() {
  testWidgets('格式刷将来源文本块的 marks 应用到另一个文本块', (tester) async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
      serverUrl: 'https://chat.example.com',
      token: 'session-token',
      documentId: 'format-painter-test',
      documentType: 'document',
      connector: (_, __) => channel,
    );
    addTearDown(session.close);

    final body = session.body;
    final source = yjs.YXmlElement('paragraph');
    source.setAttribute('textAlign', 'center');
    source.insert(0, [
      yjs.YXmlText()..insert(0, '来源文本', {'bold': true})
    ]);
    body.insert(0, [source]);
    final target = yjs.YXmlElement('paragraph');
    target.insert(0, [yjs.YXmlText()..insert(0, '目标文本')]);
    body.insert(1, [target]);

    await tester.pumpWidget(MaterialApp(
      home: DocumentEditorPage(
        repository: DemoRepository(),
        document: const ProjectDocument(
          id: 'format-painter-test',
          projectId: 'project-1',
          title: '格式刷测试',
          documentType: 'document',
        ),
        collaboration: session,
      ),
    ));
    await tester.pump();
    channel.emit(encodeHocuspocusAuthenticatedFrame(
        documentName: 'format-painter-test'));
    await tester.pump();

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'format-painter-test'));
    final syncFrame = yjs.createEncoder();
    yjs.writeVarString(syncFrame, 'format-painter-test');
    yjs.writeVarUint(syncFrame, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(syncFrame, serverDocument);
    channel.emit(yjs.toUint8Array(syncFrame));
    await tester.pump();

    await tester.pump();
    await tester.tap(find.text('来源文本'));
    await tester.pump();
    final sourceText = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .first
        .toArray()
        .whereType<yjs.YXmlText>()
        .single;
    expect(session.xmlTextMarks(sourceText), containsPair('bold', true));
    expect(session.xmlTextAlignment(sourceText), 'center');
    await tester.tap(find.byTooltip('段落背景'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('rich-document-block-background-swatch-0')));
    await tester.pumpAndSettle();
    const background = 'oklch(93.6% 0.032 17.717)';
    expect(session.xmlTextBlockBackground(sourceText), background);
    await tester.tap(find.byTooltip('格式刷'));
    await tester.pump();
    expect(find.byTooltip('取消格式刷'), findsOneWidget);
    expect(find.text('格式刷已启用 · 选择目标文本应用格式'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byTooltip('格式刷'), findsOneWidget);
    expect(find.byTooltip('取消格式刷'), findsNothing);

    await tester.tap(find.byTooltip('格式刷'));
    await tester.pump();
    await tester.tap(find.text('目标文本'));
    await tester.pump();
    final targetEditor = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('rich-document-inline-editor')),
        matching: find.byType(EditableText)));
    targetEditor.controller.selection =
        const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.pump(const Duration(milliseconds: 100));
    final targetText = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .elementAt(1)
        .toArray()
        .whereType<yjs.YXmlText>()
        .single;
    expect(session.xmlTextMarksForRange(targetText, 1, 3),
        containsPair('bold', true));
    expect(session.xmlTextMarksForRange(targetText, 0, 1), isEmpty);
    expect(session.xmlTextMarksForRange(targetText, 3, 4), isEmpty);
    expect(
        session.body
            .toArray()
            .whereType<yjs.YXmlElement>()
            .elementAt(1)
            .getAttribute('textAlign'),
        'center');
    expect(session.xmlTextBlockBackground(targetText), isNull);
    expect(find.byTooltip('格式刷'), findsOneWidget);
    expect(find.byTooltip('取消格式刷'), findsNothing);
    serverDocument.destroy();
  });

  testWidgets('原位编辑器按当前选区应用全部 marks 并让后续输入继承 stored marks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
      serverUrl: 'https://chat.example.com',
      token: 'session-token',
      documentId: 'range-format-test',
      documentType: 'document',
      connector: (_, __) => channel,
    );
    addTearDown(session.close);
    final paragraph = yjs.YXmlElement('paragraph');
    final text = yjs.YXmlText()..insert(0, 'abcdef');
    paragraph.insert(0, [text]);
    final unknown = yjs.YXmlElement('futureBlock')
      ..insert(0, [yjs.YXmlText()..insert(0, '未知兄弟节点')]);
    session.body.insert(0, [paragraph, unknown]);
    await tester.pumpWidget(MaterialApp(
      home: DocumentEditorPage(
        repository: DemoRepository(),
        document: const ProjectDocument(
          id: 'range-format-test',
          projectId: 'project-1',
          title: '区间格式测试',
          documentType: 'document',
        ),
        collaboration: session,
      ),
    ));
    await tester.pump();
    channel.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'range-format-test'));
    await tester.pump();
    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'range-format-test'));
    final syncFrame = yjs.createEncoder();
    yjs.writeVarString(syncFrame, 'range-format-test');
    yjs.writeVarUint(syncFrame, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(syncFrame, serverDocument);
    channel.emit(yjs.toUint8Array(syncFrame));
    await tester.pump();
    await tester.pump();
    expect(session.status, DocumentCollaborationStatus.synced);

    await tester.tap(find.text('abcdef'));
    await tester.pump();
    expect(find.byKey(const ValueKey('rich-document-inline-editor')),
        findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
    _inlineEditor(tester).controller.selection =
        const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.pump();
    for (final tooltip in ['粗体', '斜体', '下划线', '删除线', '行内代码']) {
      await tester.ensureVisible(find.byTooltip(tooltip));
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
    }
    await tester.ensureVisible(find.byTooltip('字体颜色'));
    await tester.tap(find.byTooltip('字体颜色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('蓝色').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('文字背景色'));
    await tester.tap(find.byTooltip('文字背景色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('黄色').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('链接'));
    await tester.tap(find.byTooltip('链接'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('rich-document-link-field')), 'example.com');
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await tester.pumpAndSettle();

    final selectedMarks = session.xmlTextMarksForRange(text, 1, 4);
    expect(selectedMarks, containsPair('bold', true));
    expect(selectedMarks, containsPair('italic', true));
    expect(selectedMarks, containsPair('underline', true));
    expect(selectedMarks, containsPair('strike', true));
    expect(selectedMarks, containsPair('code', true));
    expect(selectedMarks['textStyle'], {'color': '#2563eb'});
    expect(selectedMarks['highlight'], {'color': '#ca8a04'});
    expect(selectedMarks['link'], {'href': 'https://example.com'});
    expect(session.xmlTextMarksForRange(text, 0, 1), isEmpty);
    expect(session.xmlTextMarksForRange(text, 4, 6), isEmpty);
    expect(identical(session.body.toArray().last, unknown), isTrue);

    await tester.ensureVisible(find.byTooltip('清除格式').last);
    await tester.tap(find.byTooltip('清除格式').last);
    await tester.pump();
    expect(session.xmlTextMarksForRange(text, 1, 4), isEmpty);

    var editor = _inlineEditor(tester);
    editor.focusNode.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'aaaaaa',
      selection: TextSelection.collapsed(offset: 6),
    ));
    await tester.pump();
    editor = _inlineEditor(tester);
    editor.controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('斜体'));
    await tester.tap(find.byTooltip('斜体'));
    await tester.pump();
    editor = _inlineEditor(tester);
    editor.focusNode.requestFocus();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'aaaaaaa',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump();

    expect(text.toString(), 'aaaaaaa');
    expect(
        session.xmlTextMarksForRange(text, 1, 2), containsPair('italic', true));
    expect(session.xmlTextMarksForRange(text, 0, 1), isEmpty);
    expect(session.xmlTextMarksForRange(text, 2, 7), isEmpty);
    expect(session.undo(), isTrue);
    expect(text.toString(), 'aaaaaa');
    expect(session.redo(), isTrue);
    expect(text.toString(), 'aaaaaaa');
    expect(unknown.toString(), contains('未知兄弟节点'));
    serverDocument.destroy();
  });
}

EditableText _inlineEditor(WidgetTester tester) =>
    tester.widget<EditableText>(find.descendant(
      of: find.byKey(const ValueKey('rich-document-inline-editor')),
      matching: find.byType(EditableText),
    ));

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
