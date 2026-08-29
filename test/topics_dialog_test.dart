import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/topics_dialog.dart';

void main() {
  testWidgets('话题列表支持筛选、加载更多并打开详情', (tester) async {
    final repository = _TopicRepository();
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: ConversationTopicsDialog(
        repository: repository,
        conversationId: 'parent-1',
        onOpenTopic: (value) => opened = value,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('讨论发布计划'), findsOneWidget);
    expect(repository.statuses, ['all']);
    expect(find.text('加载更多'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('上线复盘'), findsOneWidget);
    expect(repository.cursors, [null, 'cursor-2']);

    await tester.tap(find.text('已关闭'));
    await tester.pumpAndSettle();
    expect(repository.statuses.last, 'archived');
    expect(find.text('已归档话题'), findsOneWidget);

    await tester.tap(find.text('已归档话题'));
    await tester.pumpAndSettle();
    expect(find.text('话题详情'), findsOneWidget);
    expect(find.text('来源消息'), findsOneWidget);
    await tester.tap(find.text('打开话题'));
    await tester.pumpAndSettle();
    expect(opened, 'topic-archived');
  });

  testWidgets('话题详情支持参与和关闭', (tester) async {
    final repository = _TopicRepository(canParticipate: true);
    await tester.pumpWidget(MaterialApp(
      home: TopicDetailDialog(
        repository: repository,
        conversationId: 'topic-1',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('参与话题'), findsOneWidget);
    await tester.tap(find.text('参与话题'));
    await tester.pumpAndSettle();
    expect(repository.participated, isTrue);
    expect(find.text('参与话题'), findsNothing);

    await tester.tap(find.text('关闭话题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();
    expect(repository.archived, isTrue);
  });
}

class _TopicRepository extends DemoRepository {
  _TopicRepository({this.canParticipate = false});

  final bool canParticipate;
  final cursors = <String?>[];
  final statuses = <String>[];
  bool participated = false;
  bool archived = false;

  @override
  Future<TopicPage> topics(String conversationId,
      {String? cursor, int? limit, String status = 'all'}) async {
    cursors.add(cursor);
    statuses.add(status);
    if (status == 'archived') {
      return TopicPage(
          topics: [_conversation('topic-archived', '已归档话题', true)]);
    }
    return TopicPage(
      topics: [
        _conversation('topic-1', '讨论发布计划', false),
        if (cursor != null) _conversation('topic-2', '上线复盘', false),
      ],
      nextCursor: cursor == null ? 'cursor-2' : null,
    );
  }

  @override
  Future<TopicDetail> topicDetail(String conversationId) async {
    final topic = _conversation(conversationId, '来源消息', archived);
    return TopicDetail(
      canArchive: !archived,
      canParticipate: canParticipate && !participated && !archived,
      conversation: topic,
      parentConversation:
          const TopicReference(id: 'parent-1', name: '产品群', type: 'group'),
      sourceMessage: const TopicSourceMessage(
        id: 'source-1',
        createdAt: '2026-08-29T10:00:00Z',
        sender: TopicSourceSender(id: 'user-1', type: 'user', name: 'Alice'),
        sequence: 8,
        summary: '来源消息',
        body: {'type': 'text', 'content': '来源消息'},
      ),
    );
  }

  @override
  Future<ChatConversation> participateTopic(String conversationId) async {
    participated = true;
    return _conversation(conversationId, '来源消息', false);
  }

  @override
  Future<ChatConversation> archiveTopic(String conversationId) async {
    archived = true;
    return _conversation(conversationId, '来源消息', true);
  }

  ChatConversation _conversation(String id, String title, bool isArchived) =>
      ChatConversation(
        id: id,
        title: title,
        type: 'topic',
        canSend: !isArchived,
        topic: TopicMetadata(
          archived: isArchived,
          parentConversationId: 'parent-1',
          parentConversationName: '产品群',
          parentConversationType: 'group',
          participating: participated,
          sourceMessageId: 'source-1',
          sourceMessageSeq: 8,
          sourceSender: const TopicSourceSender(
              id: 'user-1', type: 'user', name: 'Alice'),
        ),
      );
}
