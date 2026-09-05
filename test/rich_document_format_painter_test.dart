import 'dart:async';

import 'package:flutter/material.dart';
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
    await tester.tap(find.byTooltip('格式刷'));
    await tester.pump();
    expect(find.byTooltip('取消格式刷'), findsOneWidget);
    expect(find.text('格式刷已启用 · 点击其他文本块应用格式'), findsOneWidget);

    await tester.tap(find.text('目标文本'));
    await tester.pump();
    final targetText = session.body
        .toArray()
        .whereType<yjs.YXmlElement>()
        .elementAt(1)
        .toArray()
        .whereType<yjs.YXmlText>()
        .single;
    expect(
        targetText.toDelta().single['attributes'], containsPair('bold', true));
    expect(find.byTooltip('格式刷'), findsOneWidget);
    expect(find.byTooltip('取消格式刷'), findsNothing);
    serverDocument.destroy();
  });
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
