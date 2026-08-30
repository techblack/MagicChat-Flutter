import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/search/global_search.dart';

class _SearchRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
            id: 'conversation-engineering',
            title: '工程群',
            type: 'group',
            preview: 'Release Ready'),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'user-alice', name: 'Alice', email: 'alice@example.com'),
      ];

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-release', name: 'Release 计划', description: '版本发布'),
      ];

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword) async => [
        const MessageSearchResult(
            conversationId: 'conversation-engineering',
            conversationName: '工程群',
            message: ChatMessage(
                id: 'message-release', author: 'Alice', text: 'Release Ready')),
      ];
}

void main() {
  test('按会话、联系人、项目和消息分组匹配综合搜索结果', () {
    final results =
        buildGlobalSearchResults(keyword: 'release', conversations: const [
      ChatConversation(id: 'c1', title: '工程群', preview: 'Release Ready')
    ], contacts: const [
      Contact(id: 'u1', name: 'Alice')
    ], projects: const [
      Project(id: 'p1', name: 'Release 计划', description: '版本发布')
    ], messages: const [
      MessageSearchResult(
          conversationId: 'c1',
          conversationName: '工程群',
          message:
              ChatMessage(id: 'm1', author: 'Alice', text: 'Release Ready'))
    ]);

    expect(results.map((item) => item.type), [
      GlobalSearchResultType.conversation,
      GlobalSearchResultType.project,
      GlobalSearchResultType.message,
    ]);
    expect(results[0].conversation!.id, 'c1');
    expect(results[1].project!.id, 'p1');
    expect(results[2].message!.message.id, 'm1');
  });

  test('空关键词不触发任何结果', () {
    expect(
        buildGlobalSearchResults(
            keyword: '  ',
            conversations: const [],
            contacts: const [],
            projects: const [],
            messages: const []),
        isEmpty);
  });

  testWidgets('综合搜索加载本地索引并保持消息跳转', (tester) async {
    final opened = <String>[];
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlobalSearchDialog(
          repository: _SearchRepository(),
          onOpenConversation: opened.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'release');
    await tester.pumpAndSettle();
    expect(find.text('会话'), findsOneWidget);
    expect(find.text('工程群'), findsWidgets);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('Release 计划'), findsOneWidget);
    expect(find.text('聊天记录'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/global_search.png'));

    await tester.tap(find.byKey(
        const ValueKey('message:conversation-engineering:message-release')));
    await tester.pumpAndSettle();
    expect(opened, ['conversation-engineering']);
  });
}
