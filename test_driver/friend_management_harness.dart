import 'package:flutter/material.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contacts_page.dart';

void main() => runApp(const _FriendManagementHarness());

class _FriendManagementHarness extends StatelessWidget {
  const _FriendManagementHarness();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
            useMaterial3: true),
        home: Scaffold(
          appBar: AppBar(title: const Text('MagicChat 通讯录流程验证')),
          body: ContactsPage(repository: _HarnessRepository()),
        ),
      );
}

class _HarnessRepository extends DemoRepository {
  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      const ContactDirectory(contacts: [
        Contact(id: 'friend-bob', name: 'Bob', online: true),
        Contact(id: 'app-assistant', name: 'MagicChat 助手', type: 'app'),
      ], mode: 'friends');

  @override
  Future<List<Contact>> searchUsers(String query) async => const [
        Contact(id: 'user-alice', name: 'Alice', email: 'alice@example.com')
      ];

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
}
