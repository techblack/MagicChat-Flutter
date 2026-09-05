import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('拖入图片显示整区提示和预览，确认后按图片发送', (tester) async {
    final repository = _DropRepository();
    await _pumpConversation(tester, repository);

    _dropTarget(tester).onDragEntered!(DropEventDetails(
        localPosition: Offset.zero, globalPosition: Offset.zero));
    await tester.pump();
    expect(find.byKey(const ValueKey('conversation-file-drop-overlay')),
        findsOneWidget);
    expect(find.text('松开发送文件或图片'), findsOneWidget);

    final bytes =
        Uint8List.fromList(image.encodePng(image.Image(width: 80, height: 40)));
    _dropTarget(tester).onDragDone!(DropDoneDetails(
      files: [
        DropItemFile.fromData(bytes, path: 'preview.png', mimeType: 'image/png')
      ],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ));
    await tester.pumpAndSettle();

    expect(find.text('发送图片'), findsOneWidget);
    expect(find.textContaining('preview.png'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.sentImage?.name, 'preview.png');
    expect(repository.sentImage?.mimeType, 'image/png');
    expect(repository.sentFile, isNull);
  });

  testWidgets('拖入普通文件确认后按附件发送', (tester) async {
    final repository = _DropRepository();
    await _pumpConversation(tester, repository);

    _dropTarget(tester).onDragEntered!(DropEventDetails(
        localPosition: Offset.zero, globalPosition: Offset.zero));
    _dropTarget(tester).onDragDone!(DropDoneDetails(
      files: [
        DropItemFile.fromData(Uint8List.fromList([1, 2, 3]),
            path: 'requirements.pdf', mimeType: 'application/pdf')
      ],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ));
    await tester.pumpAndSettle();

    expect(find.text('发送文件'), findsOneWidget);
    expect(find.text('requirements.pdf'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.sentFile?.name, 'requirements.pdf');
    expect(repository.sentFile?.path, 'requirements.pdf');
    expect(repository.sentImage, isNull);
  });

  testWidgets('只读会话禁用文件拖放', (tester) async {
    await _pumpConversation(tester, _DropRepository(canSend: false));

    expect(_dropTarget(tester).enable, isFalse);
  });
}

DropTarget _dropTarget(WidgetTester tester) => tester.widget<DropTarget>(
    find.byKey(const ValueKey('conversation-file-drop-target')));

Future<void> _pumpConversation(
    WidgetTester tester, _DropRepository repository) async {
  await tester.binding.setSurfaceSize(const Size(700, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ConversationView(
        repository: repository,
        conversationId: 'conversation-1',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

class _DropRepository extends DemoRepository {
  _DropRepository({this.canSend = true});

  final bool canSend;
  AttachmentUpload? sentImage;
  AttachmentUpload? sentFile;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [];

  @override
  Future<List<ChatConversation>> conversations() async => [
        ChatConversation(id: 'conversation-1', title: '文件测试', canSend: canSend),
      ];

  @override
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
      {String caption = '',
      String? replyToMessageId,
      String? clientMessageId}) async {
    sentImage = upload;
  }

  @override
  Future<void> sendFile(String conversationId, AttachmentUpload upload,
      {String? replyToMessageId, String? clientMessageId}) async {
    sentFile = upload;
  }
}
