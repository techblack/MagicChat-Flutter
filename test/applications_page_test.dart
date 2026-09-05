import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/applications_page.dart';

void main() {
  testWidgets('应用管理页展示自有应用并提供生命周期菜单', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApplicationsPage(repository: DemoRepository()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('演示应用'), findsOneWidget);
    expect(find.text('已启用'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('查看接入信息'), findsOneWidget);
    expect(find.text('编辑资料'), findsOneWidget);
    expect(find.text('删除应用'), findsOneWidget);
  });

  testWidgets('部分用户访问范围使用联系人名称选择，不展示原始用户 ID', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApplicationsPage(repository: _RestrictedAppRepository()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('user-alice'), findsNothing);
    expect(find.text('可访问用户 · 已选择 1 位'), findsOneWidget);
  });
}

class _RestrictedAppRepository extends DemoRepository {
  @override
  Future<List<OwnedApp>> apps() async => const [
        OwnedApp(
          id: 'app-1',
          name: '受限应用',
          visibility: 'restricted',
          userIds: ['user-alice'],
        ),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'user-alice', name: 'Alice'),
      ];
}
