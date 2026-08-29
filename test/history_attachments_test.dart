import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/history_attachments_dialog.dart';

void main() {
  test('历史附件模型解析服务端字段', () {
    final attachment = ConversationAttachment.fromJson({
      'created_at': '2026-08-29T10:00:00Z',
      'file_id': 'file-1',
      'message_id': 'message-1',
      'name': '设计稿.pdf',
      'seq': 12,
      'size_bytes': 2048,
    });
    expect(attachment.fileId, 'file-1');
    expect(attachment.sequence, 12);
    expect(
        AttachmentPage.fromJson({
          'attachments': [attachment.toJson()],
          'next_cursor': '12',
        }).nextCursor,
        '12');
  });

  test('HTTP 仓库发送历史附件 cursor 和 limit 并解析分页', () async {
    late Uri requestUri;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requestUri = request.url;
        return http.Response(
          jsonEncode({
            'data': {
              'attachments': [
                {
                  'created_at': '2026-08-29T10:00:00Z',
                  'file_id': 'file-1',
                  'message_id': 'message-1',
                  'name': 'design.pdf',
                  'seq': 12,
                  'size_bytes': 2048,
                },
              ],
              'next_cursor': '12',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final page =
        await repository.attachments('conversation-1', cursor: '20', limit: 25);
    expect(page.attachments.single.name, 'design.pdf');
    expect(page.nextCursor, '12');
    expect(requestUri.path,
        '/api/client/conversations/conversation-1/attachments');
    expect(requestUri.queryParameters, {'cursor': '20', 'limit': '25'});
  });

  testWidgets('历史附件对话框支持加载下一页', (tester) async {
    final repository = _AttachmentRepository();
    await tester.pumpWidget(MaterialApp(
      home: HistoryAttachmentsDialog(
        repository: repository,
        conversationId: 'conversation-1',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('新文档.pdf'), findsOneWidget);
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('旧文档.pdf'), findsOneWidget);
    expect(repository.cursors, [null, 'next']);
  });
}

class _AttachmentRepository extends DemoRepository {
  final cursors = <String?>[];

  @override
  Future<AttachmentPage> attachments(String conversationId,
      {String? cursor, int limit = 50}) async {
    cursors.add(cursor);
    final item = ConversationAttachment(
      createdAt: '2026-08-29T10:00:00Z',
      fileId: cursor == null ? 'file-new' : 'file-old',
      messageId: cursor == null ? 'message-new' : 'message-old',
      name: cursor == null ? '新文档.pdf' : '旧文档.pdf',
      sequence: cursor == null ? 20 : 10,
      sizeBytes: 2048,
    );
    return AttachmentPage(
      attachments: [item],
      nextCursor: cursor == null ? 'next' : null,
    );
  }
}
