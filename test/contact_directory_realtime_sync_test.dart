import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/contact_directory_realtime_sync.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contacts_page.dart';
import 'package:magicchat_client/features/contacts/friend_management_dialog.dart';

void main() {
  test('实时好友事件严格校验 payload 并记录刷新意图', () {
    final store = RealtimeStore();

    void apply(int cursor, String event, Object payload) => store.apply({
          'cursor': cursor,
          'event': event,
          'payload': payload,
        });

    apply(1, 'friend.request.created', {'request_id': 'request-1'});
    expect(store.friendDataRevision, 1);
    expect(store.contactDirectoryRevision, 0);
    expect(store.lastFriendDataRefreshIntent, FriendDataRefreshIntent.requests);

    apply(2, 'friend.request.updated', {'request_id': '  '});
    apply(3, 'friendship.created', {'request_id': ''});
    apply(4, 'contact.directory.mode.updated', {'mode': 'unsupported'});
    apply(5, 'friend.request.created', const []);
    expect(store.friendDataRevision, 1);

    apply(6, 'friendship.deleted', <String, dynamic>{});
    expect(store.friendDataRevision, 2);
    expect(store.contactDirectoryRevision, 1);
    expect(
        store.lastFriendDataRefreshIntent, FriendDataRefreshIntent.directory);
    apply(7, 'friendship.created', {'request_id': 'request-2'});
    apply(8, 'contact.directory.mode.updated', {'mode': 'friends'});
    expect(store.friendDataRevision, 4);
    expect(store.contactDirectoryRevision, 3);
    store.reset();
    expect(store.friendDataRevision, 0);
    expect(store.contactDirectoryRevision, 0);
    expect(store.lastFriendDataRefreshIntent, isNull);
  });

  test('同一微任务合并意图，进行中事件执行尾随刷新', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final third = Completer<void>();
    final completers = [first, second, third];
    final calls = <FriendDataRefreshIntent>[];
    final scheduler = ContactDirectoryRefreshScheduler((intent) {
      calls.add(intent);
      return completers[calls.length - 1].future;
    });

    scheduler.request(FriendDataRefreshIntent.requests);
    scheduler.request(FriendDataRefreshIntent.directory);
    await Future<void>.delayed(Duration.zero);
    expect(calls, [FriendDataRefreshIntent.directory]);

    scheduler.request(FriendDataRefreshIntent.requests);
    scheduler.request(FriendDataRefreshIntent.directory);
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [
      FriendDataRefreshIntent.directory,
      FriendDataRefreshIntent.directory,
    ]);

    scheduler.request(FriendDataRefreshIntent.requests);
    second.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls.last, FriendDataRefreshIntent.requests);
    third.complete();
    await Future<void>.delayed(Duration.zero);
    scheduler.dispose();
  });

  test('单次刷新失败后仍处理新事件', () async {
    var attempts = 0;
    final scheduler = ContactDirectoryRefreshScheduler((_) async {
      attempts++;
      if (attempts == 1) throw StateError('暂时失败');
    });

    scheduler.request(FriendDataRefreshIntent.requests);
    await Future<void>.delayed(Duration.zero);
    scheduler.request(FriendDataRefreshIntent.requests);
    await Future<void>.delayed(Duration.zero);

    expect(attempts, 2);
    scheduler.dispose();
  });

  testWidgets('好友申请不刷新目录，好友关系事件原位更新联系人', (tester) async {
    final repository = _RealtimeFriendRepository();
    final store = RealtimeStore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(repository: repository, realtimeStore: store))));
    await tester.pumpAndSettle();
    expect(repository.directoryRequests, 1);
    expect(find.text('Alice'), findsOneWidget);

    store.apply({
      'cursor': 1,
      'event': 'friend.request.created',
      'payload': {'request_id': 'request-1'},
    });
    await tester.pumpAndSettle();
    expect(repository.directoryRequests, 1);

    repository.friendName = 'Bob';
    store.apply({
      'cursor': 2,
      'event': 'friendship.deleted',
      'payload': <String, dynamic>{},
    });
    await tester.pumpAndSettle();
    expect(repository.directoryRequests, 2);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('非活跃页期间的目录事件不被后续申请事件覆盖', (tester) async {
    final repository = _RealtimeFriendRepository()..friendName = 'Bob';
    final store = RealtimeStore();
    late StateSetter setHostState;
    var active = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      setHostState = setState;
      return ContactsPage(
          repository: repository, realtimeStore: store, active: active);
    }))));
    await tester.pumpAndSettle();
    expect(repository.directoryRequests, 0);

    store.apply({
      'cursor': 1,
      'event': 'friendship.created',
      'payload': <String, dynamic>{},
    });
    store.apply({
      'cursor': 2,
      'event': 'friend.request.created',
      'payload': {'request_id': 'request-1'},
    });
    setHostState(() => active = true);
    await tester.pumpAndSettle();

    expect(repository.directoryRequests, 1);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('好友管理弹窗分类刷新申请和好友目录', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RealtimeFriendRepository();
    final store = RealtimeStore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(repository: repository, realtimeStore: store))));
    await tester.pumpAndSettle();
    expect(repository.directoryRequests, 1);
    await tester.tap(find.byKey(const ValueKey('friend-management-button')));
    await tester.pumpAndSettle();
    final dialog = find.byType(FriendManagementDialog);
    expect(repository.friendRequestCalls, 2);
    expect(repository.directoryRequests, 1);

    repository.showRequest = true;
    store.apply({
      'cursor': 1,
      'event': 'friend.request.created',
      'payload': {'request_id': 'request-1'},
    });
    store.apply({
      'cursor': 2,
      'event': 'friend.request.updated',
      'payload': {'request_id': 'request-1'},
    });
    await tester.pumpAndSettle();
    expect(repository.friendRequestCalls, 4);
    expect(repository.directoryRequests, 1);
    final request = find.byKey(const ValueKey('friend-request-request-1'));
    expect(request, findsOneWidget);
    expect(find.descendant(of: request, matching: find.text('Carol')),
        findsOneWidget);

    repository.friendName = 'Bob';
    store.apply({
      'cursor': 3,
      'event': 'friendship.created',
      'payload': <String, dynamic>{},
    });
    await tester.pumpAndSettle();
    expect(repository.friendRequestCalls, 6);
    expect(repository.directoryRequests, 2);
    expect(find.descendant(of: dialog, matching: find.text('Bob')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Alice')),
        findsNothing);

    repository.mode = 'organization';
    store.apply({
      'cursor': 4,
      'event': 'contact.directory.mode.updated',
      'payload': {'mode': 'organization'},
    });
    await tester.pumpAndSettle();
    expect(find.byType(FriendManagementDialog), findsNothing);
    expect(repository.friendRequestCalls, 8);
    expect(repository.directoryRequests, 4);
  });
}

class _RealtimeFriendRepository extends DemoRepository {
  int directoryRequests = 0;
  int friendRequestCalls = 0;
  String friendName = 'Alice';
  String mode = 'friends';
  bool showRequest = false;

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async {
    directoryRequests++;
    return ContactDirectory(
      contacts: [Contact(id: 'user-friend', name: friendName)],
      mode: mode,
    );
  }

  @override
  Future<List<FriendRequest>> friendRequests(
      {String direction = 'incoming'}) async {
    friendRequestCalls++;
    if (!showRequest || direction == 'outgoing') return const [];
    return const [
      FriendRequest(id: 'request-1', userId: 'user-carol', status: 'pending'),
    ];
  }

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async =>
      userIds.contains('user-carol')
          ? const [Contact(id: 'user-carol', name: 'Carol')]
          : const [];
}
