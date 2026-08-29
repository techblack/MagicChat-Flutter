import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('HTTP 转发支持多消息、多目标和逐条/合并模式，并解析部分失败结果', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((value) async {
        request = value;
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'data': {
                'sent_count': 1,
                'failed_count': 1,
                'results': [
                  {
                    'conversation_id': 'target-1',
                    'status': 'sent',
                    'messages': [
                      {
                        'id': 'forwarded-1',
                        'seq': 4,
                        'body': {'type': 'text', 'content': '转发内容'},
                        'sender': {'id': 'user-1', 'name': 'Alice'},
                      }
                    ],
                  },
                  {
                    'conversation_id': 'target-2',
                    'status': 'failed',
                    'error': {
                      'code': 'conversation_forbidden',
                      'message': '没有权限',
                    },
                  },
                ],
              }
            })),
            200);
      }),
    );

    final result = await repository.forwardMessages(
        'source/1',
        const ForwardMessagesRequest(
            clientForwardId: '44444444-4444-4444-8444-444444444444',
            messageIds: ['message-1', 'message-2'],
            mode: ForwardMode.merged,
            targetConversationIds: ['target-1', 'target-2']));

    expect(request.method, 'POST');
    expect(request.url.path,
        '/api/client/conversations/source%2F1/messages/forward');
    expect(jsonDecode(request.body), {
      'client_forward_id': '44444444-4444-4444-8444-444444444444',
      'message_ids': ['message-1', 'message-2'],
      'mode': 'merged',
      'target_conversation_ids': ['target-1', 'target-2'],
    });
    expect(result.sentCount, 1);
    expect(result.failedCount, 1);
    expect(result.results.first.messages.single.text, '转发内容');
    expect(result.results.last.error?.code, 'conversation_forbidden');
  });

  test('DemoRepository 对已知和未知目标分别返回 sent/failed', () async {
    final result = await DemoRepository().forwardMessages(
        'welcome',
        const ForwardMessagesRequest(
            clientForwardId: 'demo-forward',
            messageIds: ['one', 'two'],
            mode: ForwardMode.separate,
            targetConversationIds: ['team', 'missing']));

    expect(result.sentCount, 1);
    expect(result.failedCount, 1);
    expect(result.results.first.messages, hasLength(2));
    expect(result.results.last.error?.code, 'conversation_not_found');
  });

  testWidgets('消息操作从会话列表选择转发目标并展示成功结果', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: DemoRepository(), conversationId: 'welcome'))));
    await tester.pump(const Duration(seconds: 1));

    await tester.longPress(find.text('Flutter 客户端正在迁移中。'));
    await tester.pumpAndSettle();
    expect(find.text('转发消息'), findsOneWidget);
    await tester.tap(find.text('转发消息'));
    await tester.pumpAndSettle();

    expect(find.text('目标会话 ID'), findsNothing);
    expect(find.text('团队群聊'), findsOneWidget);
    await tester.tap(find.text('团队群聊'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '转发'));
    await tester.pumpAndSettle();
    expect(find.text('已转发到 1 个会话'), findsOneWidget);
  });

  testWidgets('多选工具栏支持合并转发', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: DemoRepository(), conversationId: 'welcome'))));
    await tester.pump(const Duration(seconds: 1));

    await tester.longPress(find.text('你好，欢迎使用 MagicChat！'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pump();
    await tester.longPress(find.text('Flutter 客户端正在迁移中。'));
    await tester.pump();
    await tester.tap(find.byTooltip('转发所选'));
    await tester.pumpAndSettle();

    expect(find.text('转发 2 条消息'), findsOneWidget);
    expect(find.text('合并转发'), findsOneWidget);
    await tester.tap(find.text('合并转发'));
    await tester.pump();
    await tester.tap(find.text('团队群聊'));
    await tester.pump();
    expect(find.text('已选择 1 个会话'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '转发'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('已转发到 1 个会话'), findsOneWidget);
  });

  testWidgets('生成转发目标选择截图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: DemoRepository(), conversationId: 'welcome'))));
    await tester.pump(const Duration(seconds: 1));
    await tester.longPress(find.text('Flutter 客户端正在迁移中。'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转发消息'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/message_forwarding_dialog.png'));
  });
}
