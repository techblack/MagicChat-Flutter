import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';

void main() {
  test('调用恢复会话和加入公开群 API', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode({
              'data': {
                'conversation': {
                  'id': 'conversation-1',
                  'name': 'Product Group',
                  'type': 'group',
                },
              },
            }),
            200);
      }),
    );

    final restored = await repository.restoreConversation('hidden/1');
    final joined = await repository.joinGroupConversation('group/1');

    expect(restored.id, 'conversation-1');
    expect(joined.title, 'Product Group');
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /api/client/conversations/hidden%2F1/restore',
      'POST /api/client/conversations/groups/group%2F1/join',
    ]);
    expect(
        requests.every((request) =>
            request.headers['authorization'] == 'Bearer test-token'),
        isTrue);
  });

  test('调用群聊退出、解散和按类型移除 API', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'data': {}}), 200);
      }),
    );

    await repository.leaveGroupConversation('group-1');
    await repository.dissolveGroupConversation('group-1');
    await repository.removeConversationMember('group-1', 'app-1',
        memberType: 'app');

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /api/client/conversations/groups/group-1/leave',
      'DELETE /api/client/conversations/groups/group-1',
      'DELETE /api/client/conversations/groups/group-1/members/app/app-1',
    ]);
    expect(
        requests.every((request) =>
            request.headers['authorization'] == 'Bearer test-token'),
        isTrue);
  });

  test('会话列表解析 last_mentioned_seq 提醒字段', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'conversations': [
                {
                  'id': 'conversation-1',
                  'name': '工程群',
                  'type': 'group',
                  'last_message_seq': 9,
                  'last_read_seq': 5,
                  'last_mentioned_seq': 8,
                  'member_count': 12,
                }
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    );

    final conversation = (await repository.conversations()).single;

    expect(conversation.lastMentionedSeq, 8);
    expect(conversation.lastChoiceSeq, 0);
    expect(conversation.memberCount, 12);
    expect(conversation.effectiveMemberCount, 12);
  });

  testWidgets('按群成员角色展示对应群聊操作', (tester) async {
    final repository = _RoleRepository('member');
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();

    expect(find.text('修改群名称'), findsNothing);
    expect(find.text('添加群成员'), findsOneWidget);
    expect(find.text('退出群聊'), findsOneWidget);
    expect(find.text('修改群公告'), findsNothing);
    expect(find.text('修改群头像'), findsNothing);
    expect(find.text('设为公开群'), findsNothing);
    expect(find.text('移除群成员'), findsNothing);
    expect(find.text('解散群聊'), findsNothing);
  });

  testWidgets('群主可见管理、公开和解散操作', (tester) async {
    final repository = _RoleRepository('owner');
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();

    expect(find.text('修改群名称'), findsOneWidget);
    expect(find.text('修改群公告'), findsOneWidget);
    expect(find.text('修改群头像'), findsOneWidget);
    expect(find.text('设为公开群'), findsOneWidget);
    expect(find.text('移除群成员'), findsOneWidget);
    expect(find.text('解散群聊'), findsOneWidget);
    expect(find.text('退出群聊'), findsNothing);
  });
}

class _RoleRepository extends DemoRepository {
  _RoleRepository(this.role);

  final String role;

  @override
  Future<CurrentUser> currentUser() async =>
      const CurrentUser(id: 'me', name: '当前用户', email: 'me@example.com');

  @override
  Future<List<ChatConversation>> conversations() async => [
        ChatConversation(
          id: 'role-group',
          title: '角色群聊',
          type: 'group',
          members: [
            Contact(id: 'me', name: '当前用户', role: role),
            const Contact(id: 'other', name: '其他成员'),
          ],
        ),
      ];
}
