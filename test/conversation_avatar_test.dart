import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/shared/conversation_avatar.dart';

void main() {
  test('组合头像按群主、管理员、成员排序并限制四人', () {
    final members = groupAvatarMembers(const [
      Contact(id: 'raw-id', name: 'raw-id'),
      Contact(id: 'member-1', name: '成员一'),
      Contact(id: 'admin', name: '管理员', role: 'admin'),
      Contact(id: 'owner', name: '群主', role: 'owner'),
      Contact(id: 'member-2', name: '成员二'),
      Contact(id: 'member-3', name: '成员三'),
    ]);

    expect(members.map((member) => member.id),
        ['owner', 'admin', 'member-1', 'member-2']);
  });

  testWidgets('无自定义头像的三人群聊显示稳定组合布局', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConversationAvatar(
            repository: DemoRepository(),
            radius: 24,
            conversation: const ChatConversation(
              id: 'group-1',
              title: '产品群',
              type: 'group',
              members: [
                Contact(id: 'member', name: '成员'),
                Contact(id: 'owner', name: '群主', role: 'owner'),
                Contact(id: 'admin', name: '管理员', role: 'admin'),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.bySemanticsLabel('产品群'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-avatar-member-owner')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('group-avatar-member-admin')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('group-avatar-member-member')),
        findsOneWidget);
    final owner = tester
        .getTopLeft(find.byKey(const ValueKey('group-avatar-member-owner')));
    final admin = tester
        .getTopLeft(find.byKey(const ValueKey('group-avatar-member-admin')));
    final member = tester
        .getTopLeft(find.byKey(const ValueKey('group-avatar-member-member')));
    expect(owner.dy, lessThan(admin.dy));
    expect(admin.dy, member.dy);
    expect(owner.dx, greaterThan(admin.dx));
  });

  testWidgets('缺少成员资料时群聊显示群组图标而非用户首字母', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ConversationAvatar(
        repository: DemoRepository(),
        conversation: const ChatConversation(
            id: 'group-empty', title: '空群', type: 'group'),
      ),
    ));

    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    expect(find.text('空'), findsNothing);
  });
}
