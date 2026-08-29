import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('HTTP 仓库批量查询 choice 快照并保持请求顺序', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'data': {
              'conversation_id': 'conversation-1',
              'snapshots': [
                {
                  'message_id': 'choice-1',
                  'status': 'active',
                  'choice': {
                    'my_option_ids': ['yes'],
                    'response_count': 3,
                    'options': [
                      {'id': 'yes', 'response_count': 2},
                      {'id': 'no', 'response_count': 1},
                    ],
                  },
                },
                {'message_id': 'choice-2', 'status': 'revoked'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final snapshots = await repository.listChoiceSnapshots(
        'conversation-1', [' choice-1 ', 'choice-1', 'choice-2']);
    expect(request.method, 'POST');
    expect(request.url.path,
        '/api/client/conversations/conversation-1/messages/choices/query');
    expect(jsonDecode(request.body), {
      'message_ids': ['choice-1', 'choice-2']
    });
    expect(snapshots.map((snapshot) => snapshot.messageId),
        ['choice-1', 'choice-2']);
    expect(snapshots.first.choice?.myOptionIds, ['yes']);
    expect(snapshots.first.choice?.responseCount, 3);
    expect(snapshots.last.status, 'revoked');
    expect(snapshots.last.choice, isNull);
  });

  test('HTTP 仓库批量查询 reaction 快照并解析参与者', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'conversation_id': 'conversation-1',
            'snapshots': [
              {
                'message_id': 'message-1',
                'reaction_version': 4,
                'reactions': [
                  {
                    'text': '👍',
                    'count': 2,
                    'reacted_by_me': true,
                    'users': [
                      {'id': 'user-1', 'name': 'Alice'},
                      {'id': 'user-2'},
                    ],
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final snapshots =
        await repository.listReactionSnapshots('conversation-1', ['message-1']);
    expect(request.method, 'POST');
    expect(request.url.path,
        '/api/client/conversations/conversation-1/messages/reactions/query');
    expect(jsonDecode(request.body), {
      'message_ids': ['message-1']
    });
    expect(snapshots.single.reactionVersion, 4);
    expect(snapshots.single.reactions.single.reactedByMe, isTrue);
    expect(snapshots.single.reactions.single.users.last.name, isEmpty);
  });

  test('快照响应消息顺序或会话不匹配时拒绝', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'data': {
                'conversation_id': 'other-conversation',
                'snapshots': [
                  {
                    'message_id': 'message-1',
                    'reaction_version': 0,
                    'reactions': []
                  }
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

    expect(
      () => repository.listReactionSnapshots('conversation-1', ['message-1']),
      throwsA(isA<FormatException>()),
    );
  });

  testWidgets('会话历史加载后合并 choice 与 reaction 快照', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const recordChannel = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null));
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: _SnapshotRepository(),
          conversationId: 'welcome',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('选项 A · 5'), findsOneWidget);
    expect(find.text('👍 2'), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/message_snapshot.png'));
  });
}

class _SnapshotRepository extends DemoRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
          id: 'choice-1',
          conversationId: 'welcome',
          author: '演示用户',
          text: '请选择',
          contentType: 'choice',
          rawBody: {
            'type': 'choice',
            'content_type': 'text',
            'content': '请选择',
            'selection': 'single',
            'options': [
              {'id': 'a', 'label': '选项 A'},
              {'id': 'b', 'label': '选项 B'},
            ],
          },
          choice: MessageChoiceState(
            myOptionIds: [],
            responseCount: 0,
            options: [
              MessageChoiceOption(id: 'a', responseCount: 0),
              MessageChoiceOption(id: 'b', responseCount: 0),
            ],
          ),
          reactions: [
            MessageReaction(text: '👍', count: 1, reactedByMe: false),
          ],
        ),
      ];

  @override
  Future<List<MessageChoiceSnapshot>> listChoiceSnapshots(
          String conversationId, List<String> messageIds) async =>
      const [
        MessageChoiceSnapshot(
          conversationId: 'welcome',
          messageId: 'choice-1',
          status: 'active',
          choice: MessageChoiceState(
            myOptionIds: ['a'],
            responseCount: 5,
            options: [
              MessageChoiceOption(id: 'a', responseCount: 5),
              MessageChoiceOption(id: 'b', responseCount: 0),
            ],
          ),
        ),
      ];

  @override
  Future<List<MessageReactionSnapshot>> listReactionSnapshots(
          String conversationId, List<String> messageIds) async =>
      const [
        MessageReactionSnapshot(
          conversationId: 'welcome',
          messageId: 'choice-1',
          reactionVersion: 2,
          reactions: [
            MessageReaction(text: '👍', count: 2, reactedByMe: true),
          ],
        ),
      ];
}
