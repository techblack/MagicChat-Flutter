import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/conversation_draft_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/message_mention_composer.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('提及触发只读取光标前连续查询并支持拼音过滤', () {
    expect(composerMentionTrigger('你好 @xiao', 8, 8)?.query, 'xiao');
    expect(composerMentionTrigger('你好 ＠xiao', 8, 8)?.query, 'xiao');
    expect(composerMentionTrigger('你好 @xiao ai', 10, 10), isNull);
    expect(composerMentionTrigger('@xiao', 0, 5), isNull);

    final candidates = composerMentionCandidates(const [
      Contact(id: 'user-alice', name: '小爱'),
      Contact(id: 'user-bob', name: 'Bob'),
    ], 'xiao');
    expect(candidates.map((item) => item.id), ['user-alice']);

    final limited = composerMentionCandidates([
      for (var index = 0; index < 9; index++)
        Contact(id: 'user-$index', name: '成员 $index'),
    ], '');
    expect(limited, hasLength(maxComposerMentionCandidates));
    expect(limited.map((item) => item.id), [
      'all',
      'user-0',
      'user-1',
      'user-2',
      'user-3',
      'user-4',
      'user-5',
      'user-6'
    ]);
    expect(limited.map((item) => item.id), isNot(contains('user-7')));

    final inserted = insertComposerMentions(
      '@',
      const ComposerMentionTrigger(start: 0, end: 1, query: ''),
      limited.take(2),
    );
    expect(inserted.text, '{(@user/all)} {(@user/user-0)} ');
  });

  testWidgets('输入 @ 展示当前会话成员并将选择写入草稿', (tester) async {
    final repository = _MentionRepository();
    final drafts = ConversationDraftStore();
    const scope = MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me');
    await drafts.load(scope);
    await _pumpConversation(tester, repository, drafts);

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '@bo');
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-mention-candidates')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mention-user-bob')),
        findsOneWidget);
    expect(find.text('组织外用户'), findsNothing);
    expect(repository.contactRequests, 0);
    expect(repository.resolveRequests, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('composer-mention-user-bob')));
    await tester.pump();

    final value = tester.widget<TextField>(field).controller!.value;
    expect(value.text, '{(@user/user-bob)} ');
    expect(value.selection.baseOffset, value.text.length);
    expect(drafts.draftFor('group-1')?.text, value.text);
    expect(find.byKey(const ValueKey('composer-mention-candidates')),
        findsNothing);
    expect(find.byTooltip('提及成员'), findsOneWidget);
    await _unmount(tester, drafts);
  });

  testWidgets('Enter 先选择提及候选，再次 Enter 才发送', (tester) async {
    final repository = _MentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await _pumpConversation(tester, repository, drafts);

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '@');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(repository.sentMessages, isEmpty);
    expect(find.byKey(const ValueKey('composer-mention-candidates')),
        findsNothing);
    expect(tester.widget<TextField>(field).controller!.text,
        '{(@user/user-bob)} ');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(repository.sentMessages, ['{(@user/user-bob)}']);
    await _unmount(tester, drafts);
  });

  testWidgets('点击提及按钮立即展示当前群成员且不加载全组织', (tester) async {
    final repository = _MentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await _pumpConversation(tester, repository, drafts);

    await tester.tap(find.byTooltip('提及成员'));
    await tester.pumpAndSettle();

    expect(find.text('搜索群成员'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('mention-picker-user-bob')), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(repository.contactRequests, 0);
    await tester.tap(find.byKey(const ValueKey('mention-picker-user-bob')));
    await tester.pumpAndSettle();
    expect(find.text('搜索群成员'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '{(@user/user-bob)} ');
    await _unmount(tester, drafts);
  });

  testWidgets('提及成员支持多选并一次插入多个提醒标记', (tester) async {
    final repository = _MentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await _pumpConversation(tester, repository, drafts);

    await tester.tap(find.byTooltip('提及成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mention-picker-user-alice')));
    await tester.tap(find.byKey(const ValueKey('mention-picker-user-bob')));
    await tester.pump();
    expect(find.text('完成(2)'), findsOneWidget);
    await tester.tap(find.text('完成(2)'));
    await tester.pumpAndSettle();

    final value = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(value.text, '{(@user/user-alice)} {(@user/user-bob)} ');
    await _unmount(tester, drafts);
  });

  testWidgets('消息首屏尚未返回时输入 @ 仍立即展示群成员', (tester) async {
    final repository = _SlowMessageMentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: repository,
          conversationId: 'group-1',
          draftStore: drafts,
        ),
      ),
    ));
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump();
    }

    final field = find.byType(TextField);
    await tester.enterText(field, '@');
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-mention-candidates')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mention-user-bob')),
        findsOneWidget);
    await _unmount(tester, drafts);
  });

  testWidgets('会话资料尚未返回时点击提及仍会等待并打开成员列表', (tester) async {
    final repository = _SlowConversationMentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: repository,
          conversationId: 'group-1',
          draftStore: drafts,
        ),
      ),
    ));
    await tester.pump();

    final mentionButton = find.byTooltip('提及成员');
    final mentionIconButton =
        find.ancestor(of: mentionButton, matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(mentionIconButton).onPressed, isNotNull);
    await tester.tap(mentionButton);
    await tester.pump();
    expect(find.text('搜索群成员'), findsNothing);

    repository.pendingConversations.complete(const [
      ChatConversation(
        id: 'group-1',
        title: '项目群',
        type: 'group',
        members: [Contact(id: 'user-bob', name: 'Bob')],
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('搜索群成员'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('mention-picker-user-bob')), findsOneWidget);
    await _unmount(tester, drafts);
  });

  testWidgets('先输入 @ 再收到会话资料时仍展示成员候选', (tester) async {
    final repository = _SlowConversationMentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: repository,
          conversationId: 'group-1',
          draftStore: drafts,
        ),
      ),
    ));
    await tester.pump();
    final field = find.byType(TextField);
    await tester.enterText(field, '@');
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-mention-candidates')),
        findsNothing);

    repository.pendingConversations.complete(const [
      ChatConversation(
        id: 'group-1',
        title: '项目群',
        type: 'group',
        members: [Contact(id: 'user-bob', name: 'Bob')],
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-mention-candidates')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mention-user-bob')),
        findsOneWidget);
    await _unmount(tester, drafts);
  });

  testWidgets('摘要会话缺少成员时会补齐群成员候选', (tester) async {
    final repository = _MentionRepository();
    final drafts = ConversationDraftStore();
    final realtimeStore = RealtimeStore()
      ..conversations['group-1'] = const ChatConversation(
          id: 'group-1', title: '项目群', type: 'group', memberCount: 2);
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: repository,
          realtimeStore: realtimeStore,
          conversationId: 'group-1',
          draftStore: drafts,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    expect(find.byKey(const ValueKey('composer-mention-user-bob')),
        findsOneWidget);
    await _unmount(tester, drafts);
  });

  testWidgets('不在最近列表中的群聊仍可通过会话 ID 打开并提及成员', (tester) async {
    final repository = _UnlistedMentionRepository();
    final drafts = ConversationDraftStore();
    await drafts.load(const MessageCacheScope(
        serverUrl: 'https://chat.example.com', userId: 'user-me'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: repository,
          conversationId: 'hidden-group',
          draftStore: drafts,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-mention-user-bob')),
        findsOneWidget);
    expect(repository.conversationLookupCount, greaterThan(0));
    await _unmount(tester, drafts);
  });
}

Future<void> _pumpConversation(WidgetTester tester,
    _MentionRepository repository, ConversationDraftStore drafts) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ConversationView(
        repository: repository,
        conversationId: 'group-1',
        draftStore: drafts,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _unmount(
    WidgetTester tester, ConversationDraftStore drafts) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  drafts.dispose();
}

class _MentionRepository extends DemoRepository {
  int contactRequests = 0;
  int resolveRequests = 0;
  final sentMessages = <String>[];

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(
          id: 'group-1',
          title: '项目群',
          type: 'group',
          members: [
            Contact(id: 'user-alice', name: '小爱'),
            Contact(id: 'user-bob', name: 'Bob'),
            Contact(id: 'app-helper', name: '助手', type: 'app'),
          ],
        ),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async {
    contactRequests++;
    return const [Contact(id: 'user-outsider', name: '组织外用户')];
  }

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async {
    resolveRequests++;
    throw StateError('成员资料暂时不可用');
  }

  @override
  Future<void> sendMessage(String conversationId, String text,
      {String? replyToMessageId, String? clientMessageId}) async {
    sentMessages.add(text);
  }
}

class _SlowMessageMentionRepository extends _MentionRepository {
  final pendingMessages = Completer<List<ChatMessage>>();

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) =>
      pendingMessages.future;
}

class _SlowConversationMentionRepository extends _MentionRepository {
  final pendingConversations = Completer<List<ChatConversation>>();

  @override
  Future<List<ChatConversation>> conversations() => pendingConversations.future;
}

class _UnlistedMentionRepository extends _MentionRepository {
  var conversationLookupCount = 0;

  @override
  Future<List<ChatConversation>> conversations() async => const [];

  @override
  Future<ChatConversation?> conversationById(String conversationId) async {
    conversationLookupCount++;
    return const ChatConversation(
      id: 'hidden-group',
      title: '历史项目群',
      type: 'group',
      members: [Contact(id: 'user-bob', name: 'Bob')],
    );
  }
}
