import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/topics_dialog.dart';
import 'package:magicchat_client/features/messages/topic_reply_preview.dart';

void main() {
  testWidgets('生成话题列表流程截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1042, 662));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('topic-list-golden'),
        child: SizedBox(
          width: 1042,
          height: 662,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              appBar: AppBar(title: const Text('MagicChat 话题流程验证')),
              body: Center(
                child: ConversationTopicsDialog(
                  repository: _ScreenshotRepository(),
                  conversationId: 'parent-1',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('topic-list-golden')),
      matchesGoldenFile('evidence/topic_list.png'),
    );
  });

  testWidgets('生成话题回复预览截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('topic-reply-golden'),
        child: SizedBox(
          width: 420,
          height: 260,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: TopicReplyPreview(
                  topic: MessageTopic(
                    archived: false,
                    conversationId: 'topic-1',
                    recentReplies: [
                      MessageTopicReply(
                        createdAt: '2026-08-29T10:01:00Z',
                        id: 'reply-1',
                        sender: const TopicSourceSender(
                            id: 'user-1', type: 'user', name: 'Alice'),
                        summary: '请确认发布清单',
                      ),
                      MessageTopicReply(
                        createdAt: '2026-08-29T10:02:00Z',
                        id: 'reply-2',
                        sender: const TopicSourceSender(
                            id: 'user-2', type: 'user', name: 'Bob'),
                        summary: '我已完成检查',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('topic-reply-golden')),
      matchesGoldenFile('evidence/topic_reply_preview.png'),
    );
  });
}

class _ScreenshotRepository extends DemoRepository {
  @override
  Future<TopicPage> topics(String conversationId,
          {String? cursor, int? limit, String status = 'all'}) async =>
      TopicPage(topics: [
        _topic('topic-1', '九月发布说明', false, true),
        _topic('topic-2', '客户端回归清单', false, false),
        _topic('topic-3', '八月版本复盘', true, true),
      ]);

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
