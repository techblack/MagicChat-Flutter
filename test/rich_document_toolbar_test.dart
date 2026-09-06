import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_collaboration.dart';
import 'package:magicchat_client/domain/rich_document_format.dart';
import 'package:magicchat_client/features/projects/rich_document_toolbar.dart';

void main() {
  testWidgets('富文档工具栏暴露常用 block 并回调插入类型', (tester) async {
    final inserted = <RichDocumentBlockType>[];
    var undoCount = 0;
    var redoCount = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentToolbar(
                enabled: true,
                canUndo: true,
                canRedo: false,
                onUndo: () => undoCount++,
                onRedo: () => redoCount++,
                onInsert: inserted.add))));

    expect(find.bySemanticsLabel('富文档格式工具栏'), findsOneWidget);
    expect(find.byTooltip('一级标题'), findsOneWidget);
    expect(find.byTooltip('任务列表'), findsOneWidget);

    await tester.tap(find.byTooltip('撤销'));
    await tester.tap(find.byTooltip('重做'));
    expect(undoCount, 1);
    expect(redoCount, 0);

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

  testWidgets('原位工具栏可设置并清除段落背景', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? selected = 'unchanged';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentInlineToolbar(
                blockType: RichDocumentBlockType.paragraph,
                marks: const {},
                alignment: 'left',
                blockBackground: richDocumentBlockBackgroundColors.first.value,
                onToggleMark: (_) {},
                onTextColor: (_) {},
                onHighlight: (_) {},
                onAlignment: (_) {},
                onBlockBackground: (value) => selected = value,
                onEditLink: () {},
                onClearFormatting: () {},
                onTransform: (_) {},
                onInsertBefore: () {},
                onInsertAfter: () {},
                onDelete: () {},
                onDone: () {}))));

    await tester.ensureVisible(find.byTooltip('段落背景'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('段落背景'));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('rich-document-block-background-grid')));
    expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        10);
    expect(grid.childrenDelegate.estimatedChildCount, 50);
    final selectedSwatch = tester.widget<Semantics>(
        find.byKey(const ValueKey('rich-document-block-background-swatch-0')));
    expect(selectedSwatch.properties.label, '段落背景：红色 100');
    expect(selectedSwatch.properties.selected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.tap(
        find.byKey(const ValueKey('rich-document-block-background-swatch-0')));
    await tester.pumpAndSettle();
    expect(selected, richDocumentBlockBackgroundColors.first.value);

    await tester.tap(find.byTooltip('段落背景'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无段落背景'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
