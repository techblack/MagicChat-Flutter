import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contacts_page.dart';

void main() {
  testWidgets('好友模式可精确查找并发送申请', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FriendRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('friend-management-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('friend-search-field')), 'alice@example.com');
    await tester.tap(find.byTooltip('查找'));
    await tester.pumpAndSettle();

    expect(repository.lastSearch, 'alice@example.com');
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '添加好友'));
    await tester.pumpAndSettle();

    expect(repository.requestedUserId, 'user-alice');
    expect(find.text('好友申请已发送'), findsOneWidget);
  });

  testWidgets('组织通讯录不显示好友管理入口', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(
                repository: _FriendRepository(mode: 'organization')))));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('friend-management-button')), findsNothing);
  });
}

class _FriendRepository extends DemoRepository {
  _FriendRepository({this.mode = 'friends'});

  final String mode;
  String lastSearch = '';
  String requestedUserId = '';

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      ContactDirectory(
          contacts: const [Contact(id: 'friend-bob', name: 'Bob')], mode: mode);

  @override
  Future<List<Contact>> searchUsers(String query) async {
    lastSearch = query;
    return const [
      Contact(id: 'user-alice', name: 'Alice', email: 'alice@example.com')
    ];
  }

  @override
  Future<List<FriendRequest>> friendRequests(
          {String direction = 'incoming'}) async =>
      direction == 'incoming'
          ? const [
              FriendRequest(
                  id: 'request-carol', userId: 'user-carol', status: 'pending')
            ]
          : const [
              FriendRequest(
                  id: 'request-dave', userId: 'user-dave', status: 'pending')
            ];

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async {
    const users = [
      Contact(id: 'user-carol', name: 'Carol'),
      Contact(id: 'user-dave', name: 'Dave'),
    ];
    return users.where((user) => userIds.contains(user.id)).toList();
  }

  @override
  Future<void> createFriendRequest(String userId) async {
    requestedUserId = userId;
  }
}
