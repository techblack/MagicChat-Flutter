import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/document_collaboration.dart';
import 'package:magicchat_client/domain/rich_document_format.dart';
import 'package:magicchat_client/features/projects/rich_document_horizontal_rule.dart';
import 'package:magicchat_client/features/projects/rich_document_toolbar.dart';

void main() {
  testWidgets('富文档工具栏暴露常用 block 并回调插入类型', (tester) async {
    final inserted = <RichDocumentBlockType>[];
    var undoCount = 0;
    var redoCount = 0;
    var horizontalRuleCount = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentToolbar(
                enabled: true,
                canUndo: true,
                canRedo: false,
                onUndo: () => undoCount++,
                onRedo: () => redoCount++,
                onInsertHorizontalRule: () => horizontalRuleCount++,
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
    await tester.ensureVisible(find.byTooltip('插入分割线'));
    await tester.tap(find.byTooltip('插入分割线'));
    expect(inserted, [
      RichDocumentBlockType.heading1,
      RichDocumentBlockType.taskList,
    ]);
    expect(horizontalRuleCount, 1);
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

  testWidgets('复合结构的块类型菜单提供全部官方转换类型', (tester) async {
    RichDocumentBlockType? transformed;
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichDocumentInlineToolbar(
                blockType: RichDocumentBlockType.taskList,
                marks: const {},
                alignment: 'left',
                onToggleMark: (_) {},
                onTextColor: (_) {},
                onHighlight: (_) {},
                onAlignment: (_) {},
                onEditLink: () {},
                onClearFormatting: () {},
                onTransform: (type) => transformed = type,
                onInsertBefore: () {},
                onInsertAfter: () {},
                onDelete: () {},
                onDone: () {}))));

    await tester.tap(find.byTooltip('块类型'));
    await tester.pumpAndSettle();
    for (final label in [
      '正文',
      '一级标题',
      '二级标题',
      '三级标题',
      '无序列表',
      '有序列表',
      '任务列表',
      '引用',
      '代码块',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester
        .tap(find.widgetWithText(PopupMenuItem<RichDocumentBlockType>, '引用'));
    await tester.pumpAndSettle();
    expect(transformed, RichDocumentBlockType.blockquote);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏分割线设置支持四种样式和 1 到 6 像素粗细', (tester) async {
    RichDocumentHorizontalRuleDialogResult? result;
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => FilledButton(
                    onPressed: () async {
                      result = await showDialog(
                          context: context,
                          builder: (_) =>
                              const RichDocumentHorizontalRuleDialog(
                                  initialValue: (
                                    lineStyle: 'solid',
                                    thickness: 1,
                                  )));
                    },
                    child: const Text('设置分割线'))))));

    await tester.tap(find.text('设置分割线'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rich-horizontal-rule-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('双线').last);
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('rich-horizontal-rule-thickness'));
    tester.widget<Slider>(slider).onChanged!(6);
    await tester.pump();

    final preview = tester.widget<RichDocumentHorizontalRuleView>(
        find.byType(RichDocumentHorizontalRuleView));
    expect(preview.attributes, const (lineStyle: 'double', thickness: 6));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(result, const (
      attributes: (lineStyle: 'double', thickness: 6),
      deleted: false,
    ));
    expect(tester.takeException(), isNull);
  });
}
