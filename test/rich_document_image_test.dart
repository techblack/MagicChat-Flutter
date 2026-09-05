import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/rich_document_image_dialog.dart';

void main() {
  test('HTTP 按临时文件契约上传文档图片', () async {
    late http.BaseRequest request;
    late String body;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient.streaming((value, stream) async {
        request = value;
        body = utf8.decode(await stream.toBytes());
        return http.StreamedResponse(
          http.ByteStream.fromBytes(utf8.encode(jsonEncode({
            'data': {
              'file': {'id': 'file-image-1', 'size_bytes': 3}
            }
          }))),
          201,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final uploaded = await repository.uploadTemporaryFile(AttachmentUpload(
        path: '',
        name: 'diagram.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3])));

    expect(request.method, 'POST');
    expect(request.url.path, '/api/client/temporary-files');
    expect(request.headers['authorization'], 'Bearer token');
    expect(body, contains('filename="diagram.png"'));
    expect(uploaded.id, 'file-image-1');
    expect(uploaded.sizeBytes, 3);
  });

  testWidgets('图片设置面板保存 HTTPS 外链、替代文本和布局', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    RichDocumentImageDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<RichDocumentImageDialogResult>(
                context: context,
                builder: (_) => RichDocumentImageDialog(
                  repository: DemoRepository(),
                  initialValue: const (
                    alignment: 'center',
                    alt: '',
                    externalUrl: null,
                    fileId: null,
                    width: 100,
                  ),
                ),
              );
            },
            child: const Text('设置图片'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('设置图片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '在线图片'),
        'https://example.com/diagram.png');
    await tester.enterText(find.widgetWithText(TextField, '图片替代文本'), '架构图');
    await tester.tap(find.byIcon(Icons.format_align_right).hitTestable());
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await tester.pumpAndSettle();

    expect(result?.deleted, isFalse);
    expect(result?.attributes?.externalUrl, 'https://example.com/diagram.png');
    expect(result?.attributes?.fileId, isNull);
    expect(result?.attributes?.alt, '架构图');
    expect(result?.attributes?.alignment, 'right');
  });
}
