import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/document_editor_page.dart';
import 'package:magicchat_client/features/projects/markdown_editor_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('选中文本应用粗体并保留选区', () {
    final result = applyMarkdownToolbarAction(
        const TextEditingValue(
            text: '发布说明',
            selection: TextSelection(baseOffset: 0, extentOffset: 4)),
        MarkdownToolbarAction.bold);

    expect(result.text, '**发布说明**');
    expect(
        result.selection, const TextSelection(baseOffset: 2, extentOffset: 6));
  });

  test('光标位于正文时列表操作作用于整行', () {
    final result = applyMarkdownToolbarAction(
        const TextEditingValue(
            text: '第一项\n第二项', selection: TextSelection.collapsed(offset: 5)),
        MarkdownToolbarAction.taskList);

    expect(result.text, '第一项\n- [ ] 第二项');
    expect(result.selection, const TextSelection.collapsed(offset: 11));
  });

  test('链接、图片和表格插入提供可继续编辑的模板', () {
    final linked = applyMarkdownToolbarAction(
        const TextEditingValue(
            text: '正文', selection: TextSelection.collapsed(offset: 2)),
        MarkdownToolbarAction.link);
    expect(linked.text, '正文[链接文字](https://example.com)');
    expect(
        linked.selection, const TextSelection(baseOffset: 9, extentOffset: 28));

    final image = applyMarkdownToolbarAction(
        const TextEditingValue(
            text: '', selection: TextSelection.collapsed(offset: 0)),
        MarkdownToolbarAction.image);
    expect(image.text, '![图片描述](https://example.com/image.png)');
    expect(
        image.selection, const TextSelection(baseOffset: 8, extentOffset: 37));

    final table = applyMarkdownToolbarAction(
        const TextEditingValue(
            text: '', selection: TextSelection.collapsed(offset: 0)),
        MarkdownToolbarAction.table);
    expect(table.text, contains('| 列 1 | 列 2 |'));
    expect(table.selection.isCollapsed, isTrue);
    expect(table.selection.baseOffset, table.text.length);
  });

  testWidgets('Markdown 文档展示工具栏并通过按钮更新正文', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DocumentEditorPage(
            repository: DemoRepository(),
            document: const ProjectDocument(
                id: 'toolbar-document',
                projectId: 'project-1',
                title: '工具栏验收',
                documentType: 'markdown'))));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Markdown 格式工具栏'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('markdown-body-editor')), '正文');
    final boldButton = tester.widget<IconButton>(find
        .ancestor(of: find.byTooltip('粗体'), matching: find.byType(IconButton))
        .first);
    expect(boldButton.onPressed, isNotNull);
    final toolbar = tester
        .widget<MarkdownEditorToolbar>(find.byType(MarkdownEditorToolbar));
    expect(toolbar.controller.text, '正文');
    boldButton.onPressed!();
    expect(toolbar.controller.text, '正文**文本**');
    await tester.pump();

    final body = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('markdown-body-editor')),
        matching: find.byType(EditableText)));
    expect(body.controller.text, '正文**文本**');
    expect(find.byTooltip('任务列表'), findsOneWidget);
  });

  testWidgets('Markdown 工具栏流程截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1042, 662));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('markdown-toolbar-golden'),
        child: SizedBox(
            width: 1042,
            height: 662,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFF6750A4)),
                    useMaterial3: true),
                home: DocumentEditorPage(
                    repository: DemoRepository(),
                    document: const ProjectDocument(
                        id: 'toolbar-screenshot',
                        projectId: 'project-1',
                        title: 'Markdown 编辑工具栏',
                        documentType: 'markdown'))))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('markdown-body-editor')),
        '# 九月发布说明\n\n工具栏支持 Markdown 快速排版');
    await tester.pump();

    await expectLater(find.byKey(const ValueKey('markdown-toolbar-golden')),
        matchesGoldenFile('evidence/markdown_editor_toolbar.png'));
  });
}
