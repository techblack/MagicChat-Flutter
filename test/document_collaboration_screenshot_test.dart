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
  testWidgets('Markdown 协作编辑器流程截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1042, 662));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'screenshot-session',
        documentId: 'document-3',
        documentType: 'markdown',
        connector: (_, __) => channel);
    addTearDown(session.close);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('document-collaboration-golden'),
        child: SizedBox(
          width: 1042,
          height: 662,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
                useMaterial3: true),
            home: DocumentEditorPage(
              repository: DemoRepository(),
              document: const ProjectDocument(
                  id: 'document-3',
                  projectId: 'project-1',
                  title: '九月发布说明',
                  documentType: 'markdown'),
              collaboration: session,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    channel
        .emit(encodeHocuspocusAuthenticatedFrame(documentName: 'document-3'));
    await tester.pump();

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'document-3'));
    serverDocument
        .getText('markdown')!
        .insert(0, '# 九月版本发布说明\n\n- 协作正文已同步\n- 支持远端更新灌入');
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'document-3');
    yjs.writeVarUint(incoming, 0);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await tester.pump();
    await tester.pump();

    final remoteAwarenessDocument = yjs.Doc(yjs.DocOpts(guid: 'remote'));
    final remoteAwareness = yjs.Awareness(remoteAwarenessDocument);
    remoteAwareness.setLocalState({
      'user': {'name': '远端用户'}
    });
    final awarenessFrame = yjs.createEncoder();
    yjs.writeVarString(awarenessFrame, 'document-3');
    yjs.writeVarUint(awarenessFrame, HocuspocusMessageType.awareness);
    yjs.writeVarUint8Array(awarenessFrame,
        yjs.encodeAwarenessUpdate(remoteAwareness, [remoteAwareness.clientID]));
    channel.emit(yjs.toUint8Array(awarenessFrame));
    await tester.pump();
    remoteAwarenessDocument.destroy();

    expect(session.status, DocumentCollaborationStatus.synced);
    expect(find.textContaining('字 · 已同步 · 1 人在线'), findsOneWidget);
    await expectLater(
        find.byKey(const ValueKey('document-collaboration-golden')),
        matchesGoldenFile('evidence/document_collaboration.png'));
  });

  testWidgets('富文档 XmlFragment 协作编辑器流程截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1042, 662));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'screenshot-session',
        documentId: 'document-rich-3',
        documentType: 'document',
        connector: (_, __) => channel);
    addTearDown(session.close);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('document-rich-collaboration-golden'),
        child: SizedBox(
          width: 1042,
          height: 662,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
                useMaterial3: true),
            home: DocumentEditorPage(
              repository: DemoRepository(),
              document: const ProjectDocument(
                  id: 'document-rich-3',
                  projectId: 'project-1',
                  title: '富文档协作说明',
                  documentType: 'document'),
              collaboration: session,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    channel.emit(
        encodeHocuspocusAuthenticatedFrame(documentName: 'document-rich-3'));
    await tester.pump();

    final serverDocument = yjs.Doc(yjs.DocOpts(guid: 'document-rich-3'));
    final body =
        serverDocument.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _insertParagraphs(body, '团队规范\n\n富文档正文已通过 body 协作同步');
    final incoming = yjs.createEncoder();
    yjs.writeVarString(incoming, 'document-rich-3');
    yjs.writeVarUint(incoming, HocuspocusMessageType.sync);
    yjs.writeSyncStep2(incoming, serverDocument);
    channel.emit(yjs.toUint8Array(incoming));
    await tester.pump();
    await tester.pump();

    expect(session.status, DocumentCollaborationStatus.synced);
    expect(find.textContaining('字 · 已同步'), findsOneWidget);
    await expectLater(
        find.byKey(const ValueKey('document-rich-collaboration-golden')),
        matchesGoldenFile('evidence/document_collaboration_rich.png'));
    serverDocument.destroy();
  });

  testWidgets('协作断线后显示重新连接入口', (tester) async {
    final channel = _FakeChannel();
    final session = DocumentCollaborationSession(
        serverUrl: 'https://chat.example.com',
        token: 'session-token',
        documentId: 'document-reconnect',
        documentType: 'document',
        connector: (_, __) => channel);
    addTearDown(session.close);
    await tester.pumpWidget(MaterialApp(
        home: DocumentEditorPage(
            repository: DemoRepository(),
            document: const ProjectDocument(
                id: 'document-reconnect',
                projectId: 'project-1',
                title: '协作文档',
                documentType: 'document'),
            collaboration: session)));
    await tester.pump();

    channel.fail();
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('重新连接'), findsOneWidget);
    expect(find.text('协作连接已断开 · 点击右上角重新连接'), findsOneWidget);
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

  void fail() => _incoming.addError(StateError('connection lost'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  final _done = Completer<void>();

  @override
  void add(Object? event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
