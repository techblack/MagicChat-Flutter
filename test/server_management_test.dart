import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/server_store.dart';
import 'package:magicchat_client/data/session_store.dart';
import 'package:magicchat_client/features/settings/server_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('迁移旧服务器地址并保持内置项、去重和选择状态', () async {
    SharedPreferences.setMockInitialValues(
        {'magicchat.server_url': 'https://team.example.com/base/'});
    const store = ServerStore();

    var state = await store.read();
    expect(state.servers.first.id, ServerStore.officialServerId);
    expect(state.servers.first.builtIn, isTrue);
    expect(state.servers.last.url, 'https://team.example.com/base');
    expect(state.selectedServer.url, 'https://team.example.com/base');

    expect((await store.add('重复', 'https://team.example.com/base')).status,
        SaveServerStatus.duplicate);
    final added = await store.add('开发环境', 'http://localhost:8080/');
    expect(added.status, SaveServerStatus.added);
    expect(added.server?.url, 'http://localhost:8080');
    await store.select(added.server!.id, markRecent: true);

    state = await store.read();
    expect(state.selectedServerId, added.server!.id);
    expect(state.recentServerId, added.server!.id);
    expect(
        (await store.update(
                added.server!.id, '冲突', 'https://team.example.com/base'))
            .status,
        SaveServerStatus.duplicate);

    await store.remove(added.server!.id);
    state = await store.read();
    expect(state.selectedServerId, ServerStore.officialServerId);
    expect(state.recentServerId, isNull);
    expect(state.servers.map((server) => server.name),
        ['即应官方服务器', 'team.example.com']);
  });

  test('已保存账号的服务器会补入管理列表', () async {
    const store = ServerStore();
    await store.rememberAccounts(const [
      StoredAccount(
          id: 'account-1',
          serverUrl: 'https://account.example.com/workspace/',
          token: 'secret'),
    ]);

    final state = await store.read();
    expect(state.servers.last.name, 'account.example.com');
    expect(state.servers.last.url, 'https://account.example.com/workspace');
    expect(state.selectedServerId, ServerStore.officialServerId);
  });

  testWidgets('服务器管理页支持添加、修改和确认删除', (tester) async {
    const store = ServerStore();
    await store.add('测试环境', 'https://test.example.com');
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ServerManagementPage(
            store: store, activeServerUrl: officialServerUrl)));
    await _pumpUi(tester);

    expect(find.text('即应官方服务器'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.text('测试环境'), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('添加服务器').first);
    await _pumpUi(tester);
    await tester.enterText(
        find.byKey(const ValueKey('server-name-field')), '研发环境');
    await tester.enterText(find.byKey(const ValueKey('server-url-field')),
        'dev.example.com/base/');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _pumpUi(tester);
    expect(find.text('研发环境'), findsOneWidget);
    expect(find.text('https://dev.example.com/base'), findsOneWidget);

    await tester.tap(find.byTooltip('服务器操作').last);
    await _pumpUi(tester);
    await tester.tap(find.text('修改'));
    await _pumpUi(tester);
    await tester.enterText(
        find.byKey(const ValueKey('server-name-field')), '研发集群');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _pumpUi(tester);
    expect(find.text('研发集群'), findsOneWidget);

    await tester.tap(find.byTooltip('服务器操作').last);
    await _pumpUi(tester);
    await tester.tap(find.text('删除'));
    await _pumpUi(tester);
    expect(find.text('删除服务器？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpUi(tester);
    expect(find.text('研发集群'), findsNothing);
    expect(find.text('测试环境'), findsOneWidget);
  });

  testWidgets('服务器管理页面视觉基线', (tester) async {
    const store = ServerStore();
    final team = await store.add('团队生产环境', 'https://team.example.com');
    await store.add('本地开发环境', 'http://localhost:8080');
    await store.select(team.server!.id, markRecent: true);
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('server-management-golden'),
      child: SizedBox(
        width: 600,
        height: 800,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ServerManagementPage(
              store: store, activeServerUrl: officialServerUrl),
        ),
      ),
    ));
    await _pumpUi(tester);

    await expectLater(
      find.byKey(const ValueKey('server-management-golden')),
      matchesGoldenFile('evidence/server_management.png'),
    );
  });

  testWidgets('选择其他服务器需要确认并返回登录流程', (tester) async {
    const store = ServerStore();
    final added = await store.add('团队环境', 'https://team.example.com');
    StoredServer? selected;
    await tester.pumpWidget(MaterialApp(
        home: ServerManagementPage(
      store: store,
      activeServerUrl: officialServerUrl,
      onSelect: (server) async => selected = server,
    )));
    await _pumpUi(tester);

    await tester.tap(find.text('团队环境'));
    await _pumpUi(tester);
    expect(find.text('切换服务器？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '切换'));
    await _pumpUi(tester);

    expect(selected?.id, added.server?.id);
    expect((await store.read()).selectedServerId, added.server?.id);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
