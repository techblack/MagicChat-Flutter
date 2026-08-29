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

    expect(session.status, DocumentCollaborationStatus.synced);
    expect(find.textContaining('字 · 已同步'), findsOneWidget);
    await expectLater(
        find.byKey(const ValueKey('document-collaboration-golden')),
        matchesGoldenFile('evidence/document_collaboration.png'));
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
