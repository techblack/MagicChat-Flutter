import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
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
}
