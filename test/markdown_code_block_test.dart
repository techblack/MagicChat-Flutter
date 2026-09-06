import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/features/messages/markdown_code_block.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  test('从 Markdown pre AST 保留语言和代码原文', () {
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        .parseLines(['```c++', 'int main() {', '  return 0;', '}', '```']);
    final data = markdownCodeBlockData(nodes.single as md.Element);

    expect(data.language, 'c++');
    expect(data.code, 'int main() {\n  return 0;\n}');
    expect(normalizeMarkdownCodeLanguage(data.language), 'cpp');
    expect(markdownCodeLanguageLabel(data.language), 'C++');
    expect(normalizeMarkdownCodeLanguage('unknown-language'), isNull);
  });

  testWidgets('围栏代码显示语言、高亮、横向滚动并复制原文', (tester) async {
    MethodCall? clipboardCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    const code = 'def greet(name):\n    return f"Hello {name}"';
    await tester.pumpWidget(_app(
      MarkdownBody(
        data: '```py\n$code\n```',
        builders: markdownCodeBlockBuilders(),
      ),
    ));

    expect(find.text('Python'), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-code-plain')), findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('markdown-code-horizontal-scroll')));
    expect(scroll.scrollDirection, Axis.horizontal);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('markdown-code-highlighted')));

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Python 代码块'), findsOneWidget);
    semantics.dispose();

    await tester.tap(find.byTooltip('复制代码'));
    await tester.pump();
    expect(clipboardCall?.arguments, {'text': code});
    expect(find.text('代码已复制'), findsOneWidget);
  });

  testWidgets('未知语言保持可选择纯文本且不改变布局', (tester) async {
    const code = 'some unknown syntax => value';
    await tester.pumpWidget(_app(
      MarkdownBody(
        data: '```custom-lang\n$code\n```',
        builders: markdownCodeBlockBuilders(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('custom-lang'), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-code-plain')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('markdown-code-highlighted')), findsNothing);
    expect(find.text(code), findsOneWidget);
  });

  testWidgets('超大代码气泡无内层纵向滚动并在独立页面懒构建全文', (tester) async {
    final code =
        List.generate(12000, (index) => 'line $index: value').join('\n');
    expect(code.length, greaterThan(markdownCodeHighlightMaxLength));
    await tester.pumpWidget(_app(
      SizedBox(
        width: 360,
        child: MarkdownCodeBlock(code: code, language: 'typescript'),
      ),
    ));

    expect(find.byKey(const ValueKey('markdown-code-large-preview')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('markdown-code-highlighted')), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.byTooltip('查看完整代码'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    final node =
        tester.getSemantics(find.byKey(const ValueKey('markdown-code-block')));
    expect(node.label, 'TypeScript 代码块');
    expect(node.value, code);
    semantics.dispose();

    await tester.tap(find.byTooltip('查看完整代码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('markdown-code-large-lines')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-code-large-horizontal-scroll')),
        findsOneWidget);
    expect(find.text('line 0: value'), findsOneWidget);
    expect(find.text('line 11999: value'), findsNothing);
  });
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: child)),
      ),
    );

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 50 && finder.evaluate().isEmpty; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}
