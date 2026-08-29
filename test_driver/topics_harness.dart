import 'package:flutter/material.dart';

import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/topics_dialog.dart';

void main() => runApp(const _TopicsHarness());

class _TopicsHarness extends StatelessWidget {
  const _TopicsHarness();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('MagicChat 话题流程验证')),
          body: Center(
            child: ConversationTopicsDialog(
              repository: _TopicsHarnessRepository(),
              conversationId: 'parent-1',
            ),
          ),
        ),
      );
}

class _TopicsHarnessRepository extends DemoRepository {
  @override
  Future<TopicPage> topics(String conversationId,
          {String? cursor, int? limit, String status = 'all'}) async =>
      TopicPage(
        topics: [
          _topic('topic-1', '九月发布说明', false, true),
          _topic('topic-2', '客户端回归清单', false, false),
          if (status == 'archived') _topic('topic-3', '八月版本复盘', true, true),
        ],
      );

  @override
  Future<TopicDetail> topicDetail(String conversationId) async {
    final topic = _topic(conversationId, '九月发布说明', false, true);
    return TopicDetail(
      canArchive: true,
      canParticipate: false,
      conversation: topic,
      parentConversation:
          const TopicReference(id: 'parent-1', name: '产品协作群', type: 'group'),
      sourceMessage: const TopicSourceMessage(
        id: 'source-1',
        createdAt: '2026-08-29T10:00:00Z',
        sender: TopicSourceSender(id: 'user-1', type: 'user', name: 'Alice'),
        sequence: 18,
        summary: '请大家确认九月发布说明和回归范围。',
        body: {
          'type': 'text',
          'content': '请大家确认九月发布说明和回归范围。',
        },
      ),
    );
  }

  ChatConversation _topic(
          String id, String title, bool archived, bool participating) =>
      ChatConversation(
        id: id,
        title: title,
        type: 'topic',
        preview: participating ? '已确认 4 项回归任务' : '等待参与',
        canSend: !archived,
        topic: TopicMetadata(
          archived: archived,
          parentConversationId: 'parent-1',
          parentConversationName: '产品协作群',
          parentConversationType: 'group',
          participating: participating,
          sourceMessageId: 'source-1',
          sourceMessageSeq: 18,
          sourceSender: const TopicSourceSender(
              id: 'user-1', type: 'user', name: 'Alice'),
        ),
      );
}
