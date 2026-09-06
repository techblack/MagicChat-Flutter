import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/contact_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/search/global_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SearchRepository extends DemoRepository {
  var contactSearches = 0;

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
            id: 'conversation-engineering',
            title: '工程群',
            type: 'group',
            preview: 'Release Ready'),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async {
    contactSearches++;
    return const [
      Contact(id: 'user-alice', name: 'Alice', email: 'alice@example.com'),
    ];
  }

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-release', name: 'Release 计划', description: '版本发布'),
      ];

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword,
          {String? conversationId,
          String? senderId,
          DateTime? from,
          DateTime? to}) async =>
      [
        const MessageSearchResult(
            conversationId: 'conversation-engineering',
            conversationName: '工程群',
            message: ChatMessage(
                id: 'message-release',
                sequence: 42,
                author: 'Alice',
                text: 'Release Ready')),
      ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  test('会话搜索支持拼音并按精确、前缀、包含和活跃时间排序', () {
    final quality = buildGlobalSearchResults(
      keyword: '发布',
      conversations: const [
        ChatConversation(id: 'contains', title: '九月发布'),
        ChatConversation(id: 'prefix', title: '发布计划'),
        ChatConversation(id: 'exact', title: '发布'),
      ],
      contacts: const [],
      projects: const [],
      messages: const [],
    );
    final recent = buildGlobalSearchResults(
      keyword: '工程',
      conversations: const [
        ChatConversation(
            id: 'old', title: '工程旧群', lastMessageAt: '2026-09-01T00:00:00Z'),
        ChatConversation(
            id: 'new', title: '工程新群', lastMessageAt: '2026-09-07T00:00:00Z'),
      ],
      contacts: const [],
      projects: const [],
      messages: const [],
    );
    final pinyin = buildGlobalSearchResults(
      keyword: 'gc',
      conversations: const [
        ChatConversation(id: 'engineering', title: '工程群'),
      ],
      contacts: const [],
      projects: const [],
      messages: const [],
    );

    expect(quality.map((item) => item.conversation!.id),
        ['exact', 'prefix', 'contains']);
    expect(recent.map((item) => item.conversation!.id), ['new', 'old']);
    expect(pinyin.single.conversation!.id, 'engineering');
  });

  test('成员邮箱命中显示可读原因且本地分类最多返回二十项', () {
    final memberMatch = buildGlobalSearchResults(
      keyword: 'alice@example.com',
      conversations: const [
        ChatConversation(id: 'group', title: '项目群', type: 'group', members: [
          Contact(id: 'user-alice', name: 'Alice', email: 'alice@example.com'),
        ]),
      ],
      contacts: const [],
      projects: const [],
      messages: const [],
    );
    final limited = buildGlobalSearchResults(
      keyword: '成员',
      conversations: const [],
      contacts: [
        for (var index = 0; index < 25; index++)
          Contact(id: 'user-$index', name: '成员$index'),
      ],
      projects: const [],
      messages: const [],
    );

    expect(
        memberMatch.single.matchDescription, '匹配邮箱：Alice · alice@example.com');
    expect(limited, hasLength(20));
  });

  testWidgets('综合搜索加载本地索引并携带消息定位信息', (tester) async {
    final opened = <String>[];
    final openedMessages = <String>[];
    final repository = _SearchRepository();
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlobalSearchDialog(
          repository: repository,
          onOpenConversation: opened.add,
          onOpenMessage: (conversationId, messageId, messageSequence) =>
              openedMessages.add('$conversationId:$messageId:$messageSequence'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'release');
    await tester.pump(const Duration(milliseconds: 299));
    expect(repository.contactSearches, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('会话'), findsOneWidget);
    expect(find.text('工程群'), findsWidgets);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('Release 计划'), findsOneWidget);
    expect(find.text('聊天记录'), findsOneWidget);
    await tester.tap(find.text('综合搜索'));
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/global_search.png'));

    await tester.tap(find.byKey(
        const ValueKey('message:conversation-engineering:message-release')));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(openedMessages, ['conversation-engineering:message-release:42']);
  });

  testWidgets('服务端关键词未命中时仍可从账号缓存按拼音查找联系人', (tester) async {
    const scope =
        MessageCacheScope(serverUrl: 'https://chat.example.com', userId: 'me');
    await ContactCacheStore().write(scope, const [
      Contact(id: 'engineer', name: '工程师'),
    ]);
    final repository = _SearchRepositoryWithoutContacts();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlobalSearchDialog(
          repository: repository,
          cacheScope: scope,
          onOpenConversation: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'gcs');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.contactKeyword, 'gcs');
    expect(find.text('工程师'), findsOneWidget);
  });

  testWidgets('综合搜索支持键盘上下、Home/End 和 Enter 打开结果', (tester) async {
    final openedMessages = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlobalSearchDialog(
          repository: _SearchRepository(),
          onOpenConversation: (_) {},
          onOpenMessage: (conversationId, messageId, sequence) =>
              openedMessages.add('$conversationId:$messageId:$sequence'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'release');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(openedMessages, ['conversation-engineering:message-release:42']);
  });
}

class _SearchRepositoryWithoutContacts extends _SearchRepository {
  String? contactKeyword;

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async {
    contactKeyword = keyword;
    return const [];
  }
}
