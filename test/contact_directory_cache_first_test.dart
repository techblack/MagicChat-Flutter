import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/contact_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contacts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('联系人目录缓存保留目录模式', () async {
    final store = ContactCacheStore();
    await store.clearAll();
    const scope =
        MessageCacheScope(serverUrl: 'https://chat.example.com', userId: 'me');
    const directory = ContactDirectory(
        contacts: [Contact(id: 'alice', name: 'Alice')], mode: 'friends');

    await store.writeDirectory(scope, directory);

    final cached = await store.readDirectory(scope);
    expect(cached?.mode, 'friends');
    expect(cached?.contacts.single.name, 'Alice');
  });

  testWidgets('联系人首页先展示缓存并后台刷新远端目录', (tester) async {
    final store = ContactCacheStore();
    await store.clearAll();
    const scope =
        MessageCacheScope(serverUrl: 'https://chat.example.com', userId: 'me');
    await store.writeDirectory(
        scope,
        const ContactDirectory(
            contacts: [Contact(id: 'cached', name: '缓存联系人')],
            mode: 'organization'));
    final repository = _DelayedDirectoryRepository();

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(repository: repository, cacheScope: scope))));
    for (var index = 0;
        index < 8 && find.text('缓存联系人').evaluate().isEmpty;
        index++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('缓存联系人'), findsOneWidget);
    expect(repository.requests, 1);

    repository.remote.complete(const ContactDirectory(
        contacts: [Contact(id: 'remote', name: '远端联系人')],
        mode: 'organization'));
    await tester.pumpAndSettle();
    expect(find.text('远端联系人'), findsOneWidget);
    expect(find.text('缓存联系人'), findsNothing);
  });
}

class _DelayedDirectoryRepository extends DemoRepository {
  final remote = Completer<ContactDirectory>();
  var requests = 0;

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) {
    requests++;
    return remote.future;
  }
}
