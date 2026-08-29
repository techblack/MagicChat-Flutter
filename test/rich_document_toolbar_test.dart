import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_collaboration.dart';
import 'package:magicchat_client/features/projects/rich_document_toolbar.dart';

void main() {
  testWidgets('富文档工具栏暴露常用 block 并回调插入类型', (tester) async {
    final inserted = <RichDocumentBlockType>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentToolbar(enabled: true, onInsert: inserted.add))));

    expect(find.bySemanticsLabel('富文档格式工具栏'), findsOneWidget);
    expect(find.byTooltip('一级标题'), findsOneWidget);
    expect(find.byTooltip('任务列表'), findsOneWidget);

    await tester.tap(find.byTooltip('一级标题'));
    await tester.tap(find.byTooltip('任务列表'));
    expect(inserted, [
      RichDocumentBlockType.heading1,
      RichDocumentBlockType.taskList,
    ]);
  });

  testWidgets('未同步时富文档工具栏禁用所有操作', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentToolbar(
                enabled: false, onInsert: (_) => called = true))));

    await tester.tap(find.byTooltip('段落'));
    expect(called, isFalse);
  });
}
