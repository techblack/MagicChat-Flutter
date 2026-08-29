import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('长按表情打开参与者列表并按通讯录补全名称', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ReactionRepository();

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: repository, conversationId: 'welcome'))));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('👍 2'));
    await tester.pumpAndSettle();

    expect(repository.reactionUsersCalls, 1);
    expect(find.text('👍 参与者'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Alice'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Bob 通讯录'), findsOneWidget);
  });

  testWidgets('参与者列表截图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: _ReactionRepository(),
                conversationId: 'welcome'))));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('👍 2'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/message_reaction_users.png'));
  });
}

class _ReactionRepository extends DemoRepository {
  int reactionUsersCalls = 0;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'reaction-message',
            conversationId: 'welcome',
            author: 'Alice',
            text: '带表情的消息',
            reactions: [
              MessageReaction(text: '👍', count: 2, reactedByMe: false),
            ]),
      ];

  @override
  Future<List<MessageReactionUser>> listReactionUsers(
      String conversationId, String messageId,
      {required String text}) async {
    reactionUsersCalls += 1;
    return const [
      MessageReactionUser(id: 'u1', name: 'Alice'),
      MessageReactionUser(id: 'u2'),
    ];
  }

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'u1', name: '通讯录 Alice'),
        Contact(id: 'u2', name: 'Bob 通讯录'),
      ];
}
