import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/project_task_details_page.dart';

void main() {
  test('HTTP 按服务端契约发送任务对象卡片', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'data': {}}), 201);
      }),
    );

    await repository.sendEntityCard(
      'conversation-1',
      entityType: 'task',
      entityId: 'task-1',
      clientMessageId: 'client-card-1',
    );

    expect(
        request.url.path, '/api/client/conversations/conversation-1/messages');
    expect(jsonDecode(request.body), {
      'client_message_id': 'client-card-1',
      'body': {
        'type': 'entity_card',
        'entity_type': 'task',
        'entity_id': 'task-1',
      },
    });
  });

  testWidgets('任务详情选择会话发送卡片且隐藏不可发送会话', (tester) async {
    final repository = _TaskCardRepository();
    await tester.pumpWidget(MaterialApp(
      home: ProjectTaskDetailsPage(
        repository: repository,
        project: const Project(id: 'project-1', name: '发布计划'),
        task: const ProjectTask(
          id: 'task-1',
          projectId: 'project-1',
          title: '完成发布检查',
          status: 'in_progress',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('发送到会话'));
    await tester.pumpAndSettle();

    expect(find.text('发送卡片'), findsOneWidget);
    expect(find.text('完成发布检查'), findsWidgets);
    expect(find.text('工程群'), findsOneWidget);
    expect(find.text('已归档话题'), findsNothing);
    expect(find.text('只读会话'), findsNothing);

    await tester.tap(
        find.byKey(const ValueKey('send-card-conversation-conversation-1')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(repository.sentConversationId, 'conversation-1');
    expect(repository.sentEntityType, 'task');
    expect(repository.sentEntityId, 'task-1');
    expect(find.text('卡片已发送到 工程群'), findsOneWidget);
  });
}

class _TaskCardRepository extends DemoRepository {
  String? sentConversationId;
  String? sentEntityType;
  String? sentEntityId;

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
          String projectId, String taskId) async =>
      const [];

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '工程群', type: 'group'),
        ChatConversation(
            id: 'archived-topic',
            title: '已归档话题',
            type: 'topic',
            topic: TopicMetadata(
              archived: true,
              parentConversationId: 'conversation-1',
              parentConversationName: '工程群',
              parentConversationType: 'group',
              participating: true,
              sourceMessageId: 'message-1',
              sourceMessageSeq: 1,
              sourceSender:
                  TopicSourceSender(id: 'user-1', type: 'user', name: 'Alice'),
            )),
        ChatConversation(id: 'read-only', title: '只读会话', canSend: false),
      ];

  @override
  Future<void> sendEntityCard(String conversationId,
      {required String entityType,
      required String entityId,
      String? replyToMessageId,
      String? clientMessageId}) async {
    sentConversationId = conversationId;
    sentEntityType = entityType;
    sentEntityId = entityId;
  }
}
