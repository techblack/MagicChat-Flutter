import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('会话居中展示系统事件摘要', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: _SystemEventRepository(),
          conversationId: 'conversation-1',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Alice 加入群聊'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Alice 加入群聊'));
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('系统事件截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('系统事件')),
        body: ConversationView(
          repository: _SystemEventRepository(),
          conversationId: 'conversation-1',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('evidence/message_system_event.png'),
    );
  });
}

class _SystemEventRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '项目群', type: 'group'),
      ];

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
          id: 'system-1',
          author: '系统',
          contentType: 'system_event',
          rawBody: {
            'type': 'system_event',
            'event': 'group_member_joined',
            'actor': {'id': 'user-1', 'display_name': 'Alice'},
          },
          text: 'Alice 加入群聊',
        ),
      ];
}
