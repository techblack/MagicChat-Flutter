import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/topic_reply_preview.dart';

void main() {
  testWidgets('话题回复预览展示摘要并可打开话题', (tester) async {
    String? opened;
    const topic = MessageTopic(
        archived: false,
        conversationId: 'topic-1',
        recentReplies: [
          MessageTopicReply(
              createdAt: '2026-07-20T04:01:00Z',
              id: 'reply-1',
              sender: TopicSourceSender(id: 'u1', type: 'user'),
              summary: '请让 {(@user/u2)} 查看最新计划'),
        ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TopicReplyPreview(
                topic: topic,
                contactsFuture: Future.value(const [
                  Contact(id: 'u1', name: 'Alice'),
                  Contact(id: 'u2', name: 'Bob'),
                ]),
                onOpen: (id) => opened = id))));
    await tester.pumpAndSettle();

    expect(find.text('Alice：请让 @Bob 查看最新计划'), findsOneWidget);
    expect(find.textContaining('u2'), findsNothing);
    expect(find.text('查看话题'), findsOneWidget);
    await tester.tap(find.byType(TopicReplyPreview));
    expect(opened, 'topic-1');
  });
}
