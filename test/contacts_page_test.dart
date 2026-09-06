import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/main.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contacts_page.dart';
import 'package:magicchat_client/features/contacts/contact_category_page.dart';
import 'package:magicchat_client/features/contacts/entity_details_page.dart';
import 'package:magicchat_client/features/contacts/contact_directory_tile.dart';

void main() {
  testWidgets('AppShell 未打开联系人页时不加载 2000 人通讯录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _LargeDirectoryRepository();

    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: repository)));
    await tester.pumpAndSettle();

    expect(repository.requests, 0);
    expect(
        find.byKey(const ValueKey('contacts-page-inactive'),
            skipOffstage: false),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();

    expect(repository.requests, 1);
    expect(find.byType(ContactDirectoryTile).evaluate().length, lessThan(200));
  });

  testWidgets('2000 人通讯录只构建视口附近的联系人条目', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _LargeDirectoryRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pumpAndSettle();

    final builtTiles = find.byType(ContactDirectoryTile).evaluate().length;
    expect(builtTiles, greaterThan(0));
    expect(builtTiles, lessThan(200));
  });

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
    expect(find.widgetWithText(ListTile, 'Alice'), findsOneWidget);
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

  testWidgets('通讯录首页显示分类入口，用户列表不再混入应用和群组', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: ContactsPage(repository: _DirectoryRepository()))));
    await tester.pumpAndSettle();

    expect(find.text('新朋友'), findsOneWidget);
    expect(find.text('我的应用'), findsOneWidget);
    expect(find.text('所有应用'), findsOneWidget);
    expect(find.text('我加入的群组'), findsOneWidget);
    expect(find.text('公开群组'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Alice'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '智能助手'), findsNothing);
    expect(find.widgetWithText(ListTile, '公开项目群'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('contact-category-myApps')));
    await tester.pumpAndSettle();
    expect(find.byType(ContactCategoryPage), findsOneWidget);
    expect(find.widgetWithText(ListTile, '我的机器人'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '智能助手'), findsNothing);
  });

  testWidgets('联系人字母索引可跳转到对应分组', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: _AlphabetRepository()))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('contact-index-Z')));
    await tester.pump();

    final indicator = find.byKey(const ValueKey('contact-index-indicator'));
    expect(indicator, findsOneWidget);
    expect(find.descendant(of: indicator, matching: find.text('Z')),
        findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Zoe'), findsOneWidget);
  });

  testWidgets('好友管理可确认并删除已有好友', (tester) async {
    final repository = _FriendRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-management-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-friend-friend-bob')));
    await tester.pumpAndSettle();
    expect(find.text('确定删除好友“Bob”吗？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除').last);
    await tester.pumpAndSettle();
    expect(repository.deletedUserId, 'friend-bob');
    expect(find.text('已删除好友'), findsOneWidget);
  });

  testWidgets('公开群组未加入时先加入再打开会话', (tester) async {
    String? opened;
    final repository = _GroupRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(
                repository: repository,
                onOpenConversation: (id, _) => opened = id))));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('contact-category-publicGroups')));
    await tester.pumpAndSettle();
    expect(find.text('3 人 · 公开群组'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '公开群组'));
    await tester.pumpAndSettle();
    expect(find.byType(EntityDetailsPage), findsOneWidget);
    expect(repository.joinedGroupId, isNull);
    await tester.tap(find.text('加入群聊'));
    await tester.pumpAndSettle();
    expect(repository.joinedGroupId, 'group-public');
    expect(opened, 'group-public');
  });

  testWidgets('已加入但会话列表缺失时恢复群聊再打开', (tester) async {
    String? opened;
    final repository = _GroupRepository(initiallyJoined: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(
                repository: repository,
                onOpenConversation: (id, _) => opened = id))));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('contact-category-publicGroups')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '公开群组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();

    expect(repository.restoredGroupId, 'group-public');
    expect(opened, 'group-public');
  });

  testWidgets('点击联系人先展示完整资料，再从资料页发起私聊', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? opened;
    final repository = _UserDetailsRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(
                repository: repository,
                onOpenConversation: (id, _) => opened = id))));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Alice'));
    await tester.pumpAndSettle();

    expect(find.byType(EntityDetailsPage), findsOneWidget);
    expect(find.text('联系人详情'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('+8613800000000'), findsOneWidget);
    expect(find.text('user-alice'), findsNothing);
    expect(find.text('USER-ALICE'), findsNothing);
    expect(repository.directUserId, isNull);

    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();
    expect(repository.directUserId, 'user-alice');
    expect(opened, 'direct-alice');
  });

  testWidgets('应用资料展示描述、开发者和在线状态', (tester) async {
    final repository = _AppDetailsRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('contact-category-allApps')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '智能助手'));
    await tester.pumpAndSettle();

    expect(find.text('应用详情'), findsOneWidget);
    expect(find.text('帮助整理会话'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    expect(find.text('开发者小王'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('app-assistant'), findsNothing);
  });

  testWidgets('联系人列表支持下拉刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _RefreshContactsRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pumpAndSettle();
    final requestsBeforeRefresh = repository.requests;
    expect(requestsBeforeRefresh, greaterThanOrEqualTo(1));

    await tester.drag(find.text('刷新联系人'), const Offset(0, 420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(repository.requests, requestsBeforeRefresh + 1);
    expect(find.text('刷新联系人'), findsOneWidget);
  });

  testWidgets('长按联系人可多选并快速组建群聊', (tester) async {
    final repository = _SelectionRepository();
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContactsPage(
                repository: repository,
                onOpenConversation: (id, _) => opened = id))));
    await tester.pumpAndSettle();

    await tester.longPress(find.widgetWithText(ListTile, 'Alice'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Bob'));
    await tester.pump();
    expect(find.text('已选择 2 位联系人'), findsOneWidget);
    await tester.tap(find.text('组建群聊'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == '群聊名称'),
        '临时群聊');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(
        repository.memberIds, containsAll(<String>['user-alice', 'user-bob']));
    expect(opened, 'group-created');
  });

  testWidgets('联系人搜索输入后防抖查询并支持清除', (tester) async {
    final repository = _SearchContactsRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactsPage(repository: repository))));
    await tester.pumpAndSettle();

    final search = find.byType(TextField).first;
    await tester.enterText(search, 'Alice');
    await tester.pump(const Duration(milliseconds: 299));
    expect(repository.keywords, isNot(contains('Alice')));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(repository.keywords.last, 'Alice');
    expect(find.widgetWithText(ListTile, 'Alice'), findsOneWidget);
    expect(repository.keywords.where((keyword) => keyword == 'Alice'),
        hasLength(1));

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(repository.keywords.last, isEmpty);
    expect(repository.keywords, hasLength(3));
  });
}

class _FriendRepository extends DemoRepository {
  _FriendRepository({this.mode = 'friends'});

  final String mode;
  String lastSearch = '';
  String requestedUserId = '';
  String deletedUserId = '';

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

  @override
  Future<void> deleteFriend(String userId) async {
    deletedUserId = userId;
  }
}

class _DirectoryRepository extends DemoRepository {
  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      ContactDirectory(contacts: [
        Contact(id: 'user-alice', name: 'Alice'),
        Contact(
            id: 'owned-app', name: '我的机器人', type: 'app', creatorUserId: 'demo'),
        Contact(id: 'other-app', name: '智能助手', type: 'app'),
        Contact(id: 'joined-group', name: '研发群', type: 'group', joined: true),
        Contact(
            id: 'public-group',
            name: '公开项目群',
            type: 'group',
            visibility: 'public'),
      ], mode: 'friends');
}

class _SelectionRepository extends DemoRepository {
  List<String> memberIds = const [];

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      const ContactDirectory(contacts: [
        Contact(id: 'user-alice', name: 'Alice'),
        Contact(id: 'user-bob', name: 'Bob'),
      ], mode: 'organization');

  @override
  Future<ChatConversation> createGroupConversation(String name,
      {List<String> memberIds = const [],
      List<String> appIds = const []}) async {
    this.memberIds = memberIds;
    return const ChatConversation(
        id: 'group-created', title: '临时群聊', type: 'group');
  }
}

class _AlphabetRepository extends DemoRepository {
  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      ContactDirectory(contacts: [
        for (var index = 0; index < 18; index++)
          Contact(id: 'alice-$index', name: 'Alice $index'),
        const Contact(id: 'user-zoe', name: 'Zoe'),
      ], mode: 'organization');
}

class _GroupRepository extends DemoRepository {
  _GroupRepository({this.initiallyJoined = false});

  final bool initiallyJoined;
  String? joinedGroupId;
  String? restoredGroupId;

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      ContactDirectory(contacts: [
        Contact(
            id: 'group-public',
            name: '公开群组',
            type: 'group',
            joined: initiallyJoined,
            memberCount: 3,
            visibility: 'public')
      ], mode: 'organization');

  @override
  Future<ChatConversation> joinGroupConversation(String conversationId) async {
    joinedGroupId = conversationId;
    return ChatConversation(id: conversationId, title: '公开群组', type: 'group');
  }

  @override
  Future<ChatConversation> restoreConversation(String conversationId) async {
    restoredGroupId = conversationId;
    return ChatConversation(id: conversationId, title: '公开群组', type: 'group');
  }
}

class _UserDetailsRepository extends DemoRepository {
  String? directUserId;

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      const ContactDirectory(
          contacts: [Contact(id: 'user-alice', name: 'Alice')],
          mode: 'organization');

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async => const [
        Contact(
          id: 'user-alice',
          name: 'USER-ALICE',
          nickname: '小爱',
          email: 'alice@example.com',
          phone: '+8613800000000',
        ),
      ];

  @override
  Future<ChatConversation> createDirectConversation(String userId) async {
    directUserId = userId;
    return const ChatConversation(id: 'direct-alice', title: 'Alice');
  }
}

class _AppDetailsRepository extends DemoRepository {
  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      const ContactDirectory(contacts: [
        Contact(
          id: 'app-assistant',
          name: '智能助手',
          type: 'app',
          online: true,
          description: '帮助整理会话',
          creatorUserId: 'user-creator',
        ),
      ], mode: 'organization');

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async => const [
        Contact(id: 'user-creator', name: '开发者小王'),
      ];
}

class _RefreshContactsRepository extends DemoRepository {
  var requests = 0;

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async {
    requests++;
    return const ContactDirectory(
        contacts: [Contact(id: 'refresh-user', name: '刷新联系人')],
        mode: 'organization');
  }
}

class _SearchContactsRepository extends DemoRepository {
  final keywords = <String>[];

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async {
    keywords.add(keyword);
    return ContactDirectory(contacts: [
      Contact(
          id: keyword.isEmpty ? 'user-bob' : 'user-alice',
          name: keyword.isEmpty ? 'Bob' : 'Alice')
    ], mode: 'organization');
  }
}

class _LargeDirectoryRepository extends DemoRepository {
  var requests = 0;

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async {
    requests++;
    return ContactDirectory(contacts: [
      for (var index = 0; index < 2000; index++)
        Contact(id: 'user-$index', name: '成员 $index')
    ], mode: 'organization');
  }
}
