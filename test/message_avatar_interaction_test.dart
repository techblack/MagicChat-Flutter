import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('群聊点击成员头像进入私聊', (tester) async {
    final repository = _AvatarRepository(type: 'group');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: repository, conversationId: 'group'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message-avatar-message-1')));
    await tester.pumpAndSettle();

    expect(repository.directUserId, 'user-1');
  });

  testWidgets('私聊点击成员头像显示资料面板', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: _AvatarRepository(type: 'direct'),
                conversationId: 'direct'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message-avatar-message-1')));
    await tester.pumpAndSettle();

    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });
}

class _AvatarRepository extends DemoRepository {
  _AvatarRepository({required this.type});

  final String type;
  String? directUserId;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'message-1',
            conversationId: 'conversation',
            authorId: 'user-1',
            author: 'Alice',
            text: '你好'),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(
            id: 'user-1',
            name: 'Alice',
            nickname: '小爱',
            email: 'alice@example.com',
            avatar: ''),
      ];

  @override
  Future<List<ChatConversation>> conversations() async => [
        ChatConversation(
            id: type == 'group' ? 'group' : 'direct',
            title: type == 'group' ? '测试群' : 'Alice',
            type: type,
            members: const [
              Contact(
                  id: 'user-1',
                  name: 'Alice',
                  nickname: '小爱',
                  email: 'alice@example.com'),
            ]),
      ];

  @override
  Future<ChatConversation> createDirectConversation(String userId) async {
    directUserId = userId;
    return const ChatConversation(id: 'direct-user-1', title: 'Alice');
  }
}
