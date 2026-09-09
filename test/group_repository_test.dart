import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/group_visibility_confirmation.dart';
import 'package:magicchat_client/main.dart';

void main() {
  test('群公开状态确认文案覆盖公开和私有影响', () {
    expect(groupVisibilityConfirmationTitle(true), '设为公开群聊？');
    expect(
        groupVisibilityImpactDescription(true), contains('所有用户都可以在通讯录中发现并加入'));
    expect(groupVisibilityConfirmationTitle(false), '设为私有群聊？');
    expect(
        groupVisibilityImpactDescription(false), contains('未加入的用户将不能再从通讯录加入'));
  });

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

  test('可通过会话 ID 查询不在最近列表中的会话', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode({
              'data': {
                'conversations': [
                  {
                    'id': 'hidden/group-1',
                    'name': '历史项目群',
                    'type': 'group',
                    'members': [
                      {'id': 'user-1', 'name': 'Alice', 'type': 'user'}
                    ],
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

    final conversation = await repository.conversationById('hidden/group-1');

    expect(conversation?.displayTitle, '历史项目群');
    expect(conversation?.members.single.displayName, 'Alice');
    expect(requests.single.url.queryParameters['include_conversation_id'],
        'hidden/group-1');
    expect(requests.single.headers['authorization'], 'Bearer test-token');
  });

  testWidgets('按群成员角色展示对应群聊操作', (tester) async {
    final repository = _RoleRepository('member');
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();

    expect(find.text('修改群名称'), findsOneWidget);
    expect(find.text('添加群成员'), findsOneWidget);
    expect(find.text('退出群聊'), findsOneWidget);
    expect(find.text('修改群公告'), findsNothing);
    expect(find.text('修改群头像'), findsNothing);
    expect(find.text('设为公开群'), findsNothing);
    expect(find.text('移除群成员'), findsNothing);
    expect(find.text('解散群聊'), findsNothing);

    await tester.tap(find.text('修改群名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '成员修改群名');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.renamedTo, '成员修改群名');
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

  testWidgets('长按菜单切换群公开状态需确认并在成功后刷新', (tester) async {
    final repository = _RoleRepository('owner');
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为公开群'));
    await tester.pumpAndSettle();

    expect(find.text('设为公开群聊？'), findsOneWidget);
    expect(find.textContaining('所有用户都可以在通讯录中发现并加入'), findsOneWidget);
    expect(repository.visibilityChanges, isEmpty);
    await tester.tap(find.byKey(const ValueKey('group-visibility-cancel')));
    await tester.pumpAndSettle();
    expect(repository.visibilityChanges, isEmpty);
    expect(repository.isPublic, isFalse);

    repository.visibilityCompleter = Completer<void>();
    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为公开群'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-visibility-confirm')));
    await tester.pump();

    expect(repository.visibilityChanges, [true]);
    expect(repository.isPublic, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('group-visibility-confirm')))
            .onPressed,
        isNull);

    repository.visibilityCompleter!.complete();
    await tester.pumpAndSettle();
    expect(repository.isPublic, isTrue);
    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();
    expect(find.text('设为私有群'), findsOneWidget);
  });

  testWidgets('群主可从长按菜单的应用分组邀请应用', (tester) async {
    final repository = _RoleRepository('owner');
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('角色群聊'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加群成员'));
    await tester.tap(find.text('添加群成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '自动化助手'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(repository.addedMemberIds, isEmpty);
    expect(repository.addedAppIds, ['app-helper']);
  });
}

class _RoleRepository extends DemoRepository {
  _RoleRepository(this.role);

  final String role;
  String? renamedTo;
  bool isPublic = false;
  final visibilityChanges = <bool>[];
  Completer<void>? visibilityCompleter;
  List<String> addedMemberIds = const [];
  List<String> addedAppIds = const [];

  @override
  Future<void> renameGroupConversation(
      String conversationId, String name) async {
    renamedTo = name;
  }

  @override
  Future<void> setGroupVisibility(String conversationId, bool value) async {
    visibilityChanges.add(value);
    await visibilityCompleter?.future;
    isPublic = value;
  }

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'user-new', name: '新成员'),
        Contact(id: 'app-helper', name: '自动化助手', type: 'app'),
      ];

  @override
  Future<void> addConversationMembers(String conversationId,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {
    addedMemberIds = List.of(memberIds);
    addedAppIds = List.of(appIds);
  }

  @override
  Future<CurrentUser> currentUser() async =>
      const CurrentUser(id: 'me', name: '当前用户', email: 'me@example.com');

  @override
  Future<List<ChatConversation>> conversations() async => [
        ChatConversation(
          id: 'role-group',
          title: '角色群聊',
          type: 'group',
          isPublic: isPublic,
          members: [
            Contact(id: 'me', name: '当前用户', role: role),
            const Contact(id: 'other', name: '其他成员'),
          ],
        ),
      ];
}
