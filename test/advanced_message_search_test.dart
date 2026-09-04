import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/search/advanced_message_search_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('消息类型筛选覆盖文本组合与独立消息类型', () {
    const markdown = ChatMessage(
        id: 'markdown', author: 'Alice', text: '说明', contentType: 'markdown');
    const image = ChatMessage(
        id: 'image', author: 'Alice', text: '图片', contentType: 'image');

    expect(
        matchesConversationMessageType(
            markdown, ConversationMessageTypeFilter.text),
        isTrue);
    expect(
        matchesConversationMessageType(
            image, ConversationMessageTypeFilter.image),
        isTrue);
    expect(
        matchesConversationMessageType(
            image, ConversationMessageTypeFilter.text),
        isFalse);
  });

  testWidgets('会话高级检索传递会话与发送人并在客户端过滤类型', (tester) async {
    final repository = _AdvancedSearchRepository();
    final opened = <String>[];
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdvancedMessageSearchDialog(
          repository: repository,
          conversationId: 'conversation-1',
          conversationName: '研发群',
          onOpenMessage: (conversationId, messageId, sequence) =>
              opened.add('$conversationId:$messageId:$sequence'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('研发群 · 高级检索'), findsOneWidget);
    expect(find.text('全部时间'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('advanced-message-search-keyword')), '发布计划');
    await tester
        .tap(find.byKey(const ValueKey('advanced-message-search-sender')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice').last);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('advanced-message-search-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片').last);
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('advanced-message-search-submit')));
    await tester.pumpAndSettle();

    expect(repository.keyword, '发布计划');
    expect(repository.conversationId, 'conversation-1');
    expect(repository.senderId, 'user-1');
    expect(find.text('图片结果'), findsOneWidget);
    expect(find.text('文本结果'), findsNothing);

    await tester.tap(find
        .byKey(const ValueKey('advanced-message-search-result-message-image')));
    await tester.pumpAndSettle();
    expect(opened, ['conversation-1:message-image:12']);
  });

  testWidgets('可不输入关键词按类型检索本地缓存', (tester) async {
    final store = _SearchCacheStore();
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-1');

    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdvancedMessageSearchDialog(
          repository: _AdvancedSearchRepository(),
          conversationId: 'conversation-1',
          conversationName: '研发群',
          cacheScope: scope,
          conversationType: 'group',
          messageCacheStore: store,
          onOpenMessage: (_, __, ___) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('advanced-message-search-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片').last);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('advanced-message-search-submit')));
    await tester.pumpAndSettle();

    expect(find.text('[图片]'), findsOneWidget);
    expect(find.text('缓存文本'), findsNothing);
  });
}

class _SearchCacheStore extends MessageCacheStore {
  @override
  Future<List<Map<String, dynamic>>> search(
    MessageCacheScope scope,
    String? conversationId, {
    String keyword = '',
    String? senderId,
    DateTime? from,
    DateTime? to,
    Iterable<String> contentTypes = const [],
    String conversationType = 'direct',
    int limit = 100,
  }) async {
    final values = [
      {
        'id': 'cached-text',
        'conversation_id': 'conversation-1',
        'sequence': 1,
        'created_at': '2026-09-04T08:00:00Z',
        'author': 'Alice',
        'author_id': 'user-1',
        'content_type': 'text',
        'text': '缓存文本',
      },
      {
        'id': 'cached-image',
        'conversation_id': 'conversation-1',
        'sequence': 2,
        'created_at': '2026-09-04T09:00:00Z',
        'author': 'Alice',
        'author_id': 'user-1',
        'content_type': 'image',
        'text': '[图片]',
      },
    ];
    final types = contentTypes.toSet();
    return values
        .where((value) =>
            types.isEmpty || types.contains(value['content_type'] as String))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {}
}

class _AdvancedSearchRepository extends DemoRepository {
  String keyword = '';
  String? conversationId;
  String? senderId;

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
          id: 'conversation-1',
          title: '研发群',
          type: 'group',
          members: [Contact(id: 'user-1', name: 'Alice')],
        ),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'user-1', name: 'Alice'),
      ];

  @override
  Future<List<MessageSearchResult>> searchMessages(String keyword,
      {String? conversationId,
      String? senderId,
      DateTime? from,
      DateTime? to}) async {
    this.keyword = keyword.trim();
    this.conversationId = conversationId;
    this.senderId = senderId;
    return const [
      MessageSearchResult(
        conversationId: 'conversation-1',
        conversationName: '研发群',
        message: ChatMessage(
          id: 'message-text',
          sequence: 11,
          createdAt: '2026-09-04T08:00:00Z',
          author: 'Alice',
          authorId: 'user-1',
          text: '文本结果',
        ),
      ),
      MessageSearchResult(
        conversationId: 'conversation-1',
        conversationName: '研发群',
        message: ChatMessage(
          id: 'message-image',
          sequence: 12,
          createdAt: '2026-09-04T09:00:00Z',
          author: 'Alice',
          authorId: 'user-1',
          text: '图片结果',
          contentType: 'image',
        ),
      ),
    ];
  }
}
