import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/document_editor_page.dart';
import 'package:magicchat_client/features/projects/projects_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('HTTP 读取文档并按服务端契约发送文档卡片', () async {
    http.Request? sendRequest;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
              jsonEncode({
                'data': {
                  'id': 'document-1',
                  'project_id': 'project-1',
                  'title': '发布说明',
                  'kind': 'document',
                  'document_type': 'markdown',
                }
              }),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              });
        }
        sendRequest = request;
        return http.Response(jsonEncode({'data': {}}), 201);
      }),
    );

    final document = await repository.document('document-1');
    await repository.sendCard(
      'conversation-1',
      title: '文档 - 发布说明',
      description: '项目: 发布计划',
      url: '/documents/markdown/document-1',
      clientMessageId: 'client-card-1',
    );

    expect(document.documentType, 'markdown');
    expect(sendRequest?.url.path,
        '/api/client/conversations/conversation-1/messages');
    expect(jsonDecode(sendRequest!.body), {
      'client_message_id': 'client-card-1',
      'body': {
        'type': 'card',
        'title': '文档 - 发布说明',
        'description': '项目: 发布计划',
        'url': '/documents/markdown/document-1',
      },
    });
  });

  testWidgets('文档编辑器可选择会话发送文档卡片', (tester) async {
    final repository = _DocumentCardRepository();
    await tester.pumpWidget(MaterialApp(
      home: DocumentEditorPage(
        repository: repository,
        projectName: '发布计划',
        document: _DocumentCardRepository.documentValue,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('发送到会话'));
    await tester.pumpAndSettle();
    expect(find.text('文档 - 发布说明'), findsOneWidget);
    expect(find.text('项目：发布计划'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('send-card-conversation-conversation-1')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(repository.sentTitle, '文档 - 发布说明');
    expect(repository.sentDescription, '项目: 发布计划');
    expect(repository.sentUrl, '/documents/markdown/document-1');
    expect(find.text('卡片已发送到 工程群'), findsOneWidget);
  });

  testWidgets('项目页收到文档目标后直接打开对应文档', (tester) async {
    final repository = _DocumentCardRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectsPage(
          repository: repository,
          initialDocumentId: 'document-1',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(DocumentEditorPage), findsOneWidget);
    expect(find.text('发布说明'), findsOneWidget);
    expect(repository.requestedDocumentId, 'document-1');
  });

  test('文档卡片标题限制为 256 个字符', () {
    final title = createDocumentCardTitle(List.filled(300, '文').join());
    expect(title.characters.length, 256);
    expect(title, endsWith('…'));
  });

  test('富文档链接补全 HTTPS 并拒绝危险协议', () {
    expect(normalizeRichDocumentLink('example.com/docs'),
        'https://example.com/docs');
    expect(normalizeRichDocumentLink('mailto:user@example.com'),
        'mailto:user@example.com');
    expect(normalizeRichDocumentLink('javascript:alert(1)'), isNull);
    expect(normalizeRichDocumentLink('https://exa mple.com'), isNull);
  });
}

class _DocumentCardRepository extends DemoRepository {
  static const documentValue = ProjectDocument(
    id: 'document-1',
    projectId: 'project-1',
    title: '发布说明',
    documentType: 'markdown',
  );

  String? requestedDocumentId;
  String? sentTitle;
  String? sentDescription;
  String? sentUrl;

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-1', name: '发布计划'),
      ];

  @override
  Future<ProjectDocument> document(String documentId) async {
    requestedDocumentId = documentId;
    return documentValue;
  }

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '工程群', type: 'group'),
      ];

  @override
  Future<void> sendCard(String conversationId,
      {required String title,
      required String description,
      required String url,
      String? replyToMessageId,
      String? clientMessageId}) async {
    sentTitle = title;
    sentDescription = description;
    sentUrl = url;
  }
}
