import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight_core.dart' as hl;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/dockerfile.dart';
import 'package:highlight/languages/fsharp.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/markdown.dart' as highlight_markdown;
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/powershell.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:markdown/markdown.dart' as md;

const markdownCodeHighlightMaxLength = 100000;
const _highlightCacheLimit = 200;

class MarkdownCodeBlockData {
  const MarkdownCodeBlockData({required this.code, required this.language});

  final String code;
  final String language;
}

MarkdownCodeBlockData markdownCodeBlockData(md.Element element) {
  md.Element? codeElement;
  for (final child in element.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'code') {
      codeElement = child;
      break;
    }
  }
  final className = codeElement?.attributes['class'] ?? '';
  final language = RegExp(r'(?:^|\s)language-([^\s]+)')
          .firstMatch(className)
          ?.group(1)
          ?.trim()
          .toLowerCase() ??
      '';
  final source = codeElement?.textContent ?? element.textContent;
  return MarkdownCodeBlockData(
    code:
        source.endsWith('\n') ? source.substring(0, source.length - 1) : source,
    language: language,
  );
}

Map<String, MarkdownElementBuilder> markdownCodeBlockBuilders() =>
    {'pre': MarkdownCodeBlockBuilder()};

class MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final data = markdownCodeBlockData(element);
    return MarkdownCodeBlock(code: data.code, language: data.language);
  }
}

class MarkdownCodeBlock extends StatefulWidget {
  const MarkdownCodeBlock({
    required this.code,
    required this.language,
    super.key,
  });

  final String code;
  final String language;

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  final _horizontalController = ScrollController();

  @override
  void didUpdateWidget(covariant MarkdownCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code && _horizontalController.hasClients) {
      _horizontalController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('代码已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final normalizedLanguage = normalizeMarkdownCodeLanguage(widget.language);
    final displayLanguage = markdownCodeLanguageLabel(widget.language);
    final large = widget.code.length > markdownCodeHighlightMaxLength;
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
              fontFamily: 'monospace',
              height: 1.45,
            ) ??
        TextStyle(
          color: colors.onSurface,
          fontFamily: 'monospace',
          height: 1.45,
        );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$displayLanguage 代码块',
      value: widget.code,
      child: Container(
        key: const ValueKey('markdown-code-block'),
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CodeBlockHeader(
              language: displayLanguage,
              onCopy: () => _copy(context),
              onOpen: large
                  ? () => showDialog<void>(
                        context: context,
                        builder: (_) => _LargeCodeDialog(
                          code: widget.code,
                          language: displayLanguage,
                          onCopy: () => _copy(context),
                        ),
                      )
                  : null,
            ),
            Divider(height: 1, color: colors.outlineVariant),
            if (large)
              _LargeCodePreview(code: widget.code, style: baseStyle)
            else
              ExcludeSemantics(
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const ValueKey('markdown-code-horizontal-scroll'),
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    child: FutureBuilder<List<_HighlightedToken>?>(
                      future: normalizedLanguage == null
                          ? null
                          : _highlightMarkdownCode(
                              widget.code, normalizedLanguage),
                      builder: (context, snapshot) {
                        final tokens = snapshot.data;
                        if (tokens == null) {
                          return SelectableText(
                            widget.code,
                            key: const ValueKey('markdown-code-plain'),
                            maxLines: null,
                            style: baseStyle,
                          );
                        }
                        return SelectableText.rich(
                          TextSpan(
                            style: baseStyle,
                            children: [
                              for (final token in tokens)
                                TextSpan(
                                  text: token.text,
                                  style: _tokenStyle(context, token.className),
                                ),
                            ],
                          ),
                          key: const ValueKey('markdown-code-highlighted'),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeBlockHeader extends StatelessWidget {
  const _CodeBlockHeader({
    required this.language,
    required this.onCopy,
    this.onOpen,
  });

  final String language;
  final VoidCallback onCopy;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  language,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            if (onOpen != null)
              IconButton(
                key: const ValueKey('markdown-code-open'),
                tooltip: '查看完整代码',
                onPressed: onOpen,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_full, size: 18),
              ),
            IconButton(
              key: const ValueKey('markdown-code-copy'),
              tooltip: '复制代码',
              onPressed: onCopy,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
      );
}

class _LargeCodePreview extends StatelessWidget {
  const _LargeCodePreview({required this.code, required this.style});

  final String code;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    const maxPreviewLines = 12;
    const maxPreviewCharactersPerLine = 1000;
    final lines = code.split('\n');
    final preview = lines.take(maxPreviewLines).map((line) {
      if (line.length <= maxPreviewCharactersPerLine) return line;
      return '${line.substring(0, maxPreviewCharactersPerLine)}…';
    }).join('\n');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ExcludeSemantics(
        child: Text(
          lines.length > maxPreviewLines ? '$preview\n…' : preview,
          key: const ValueKey('markdown-code-large-preview'),
          maxLines: maxPreviewLines + 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: style,
        ),
      ),
    );
  }
}

class _LargeCodeDialog extends StatefulWidget {
  const _LargeCodeDialog({
    required this.code,
    required this.language,
    required this.onCopy,
  });

  final String code;
  final String language;
  final VoidCallback onCopy;

  @override
  State<_LargeCodeDialog> createState() => _LargeCodeDialogState();
}

class _LargeCodeDialogState extends State<_LargeCodeDialog> {
  final _horizontalController = ScrollController();
  final _verticalController = ScrollController();
  late final List<String> _lines = widget.code.split('\n');

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          height: 1.45,
        );
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.language} 代码'),
          actions: [
            IconButton(
              tooltip: '复制代码',
              onPressed: widget.onCopy,
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        body: LayoutBuilder(builder: (context, constraints) {
          final width = _estimatedCodeWidth(_lines, style?.fontSize ?? 14)
              .clamp(constraints.maxWidth, double.infinity);
          return Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey('markdown-code-large-horizontal-scroll'),
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    key: const ValueKey('markdown-code-large-lines'),
                    controller: _verticalController,
                    padding: const EdgeInsets.all(12),
                    itemExtent: (style?.fontSize ?? 14) * 1.45,
                    itemCount: _lines.length,
                    itemBuilder: (context, index) => SelectableText(
                      _lines[index],
                      maxLines: 1,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

double _estimatedCodeWidth(List<String> lines, double fontSize) {
  var maxColumns = 1;
  for (final line in lines) {
    var columns = 0;
    for (final rune in line.runes) {
      columns += rune <= 0x7f ? 1 : 2;
    }
    if (columns > maxColumns) maxColumns = columns;
  }
  return maxColumns * fontSize * .64 + 24;
}

String markdownCodeLanguageLabel(String language) {
  final value = language.trim().toLowerCase();
  final normalized = normalizeMarkdownCodeLanguage(value);
  return switch (normalized) {
    'bash' => 'Bash',
    'cpp' => 'C++',
    'cs' => 'C#',
    'css' => 'CSS',
    'dart' => 'Dart',
    'dockerfile' => 'Dockerfile',
    'fsharp' => 'F#',
    'go' => 'Go',
    'java' => 'Java',
    'javascript' => 'JavaScript',
    'json' => 'JSON',
    'kotlin' => 'Kotlin',
    'markdown' => 'Markdown',
    'php' => 'PHP',
    'powershell' => 'PowerShell',
    'python' => 'Python',
    'ruby' => 'Ruby',
    'rust' => 'Rust',
    'sql' => 'SQL',
    'swift' => 'Swift',
    'typescript' => 'TypeScript',
    'xml' => value == 'html' ? 'HTML' : 'XML',
    'yaml' => 'YAML',
    _ => value.isEmpty
        ? '代码'
        : value.length > 32
            ? value.substring(0, 32)
            : value,
  };
}

String? normalizeMarkdownCodeLanguage(String language) {
  final value = language.trim().toLowerCase();
  const aliases = {
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'c': 'cpp',
    'cc': 'cpp',
    'c++': 'cpp',
    'h': 'cpp',
    'hpp': 'cpp',
    'c#': 'cs',
    'csharp': 'cs',
    'f#': 'fsharp',
    'fs': 'fsharp',
    'golang': 'go',
    'js': 'javascript',
    'jsx': 'javascript',
    'kt': 'kotlin',
    'md': 'markdown',
    'ps1': 'powershell',
    'py': 'python',
    'rb': 'ruby',
    'rs': 'rust',
    'ts': 'typescript',
    'tsx': 'typescript',
    'html': 'xml',
    'htm': 'xml',
    'svg': 'xml',
    'yml': 'yaml',
  };
  final normalized = aliases[value] ?? value;
  return _languageMode(normalized) == null ? null : normalized;
}

hl.Mode? _languageMode(String language) => switch (language) {
      'bash' => bash,
      'cpp' => cpp,
      'cs' => cs,
      'css' => css,
      'dart' => dart,
      'dockerfile' => dockerfile,
      'fsharp' => fsharp,
      'go' => go,
      'java' => java,
      'javascript' => javascript,
      'json' => json,
      'kotlin' => kotlin,
      'markdown' => highlight_markdown.markdown,
      'php' => php,
      'powershell' => powershell,
      'python' => python,
      'ruby' => ruby,
      'rust' => rust,
      'sql' => sql,
      'swift' => swift,
      'typescript' => typescript,
      'xml' => xml,
      'yaml' => yaml,
      _ => null,
    };

class _HighlightedToken {
  const _HighlightedToken(this.text, this.className);

  final String text;
  final String? className;
}

final _highlightCache = <String, Future<List<_HighlightedToken>?>>{};

Future<List<_HighlightedToken>?> _highlightMarkdownCode(
  String code,
  String language,
) {
  final key = '$language\u0000$code';
  final cached = _highlightCache[key];
  if (cached != null) return cached;
  if (_highlightCache.length >= _highlightCacheLimit) {
    _highlightCache.remove(_highlightCache.keys.first);
  }
  final future = compute<Map<String, String>, List<Map<String, String?>>?>(
    _highlightInBackground,
    {'code': code, 'language': language},
  ).then((tokens) => tokens
      ?.map((token) => _HighlightedToken(token['text'] ?? '', token['class']))
      .toList(growable: false));
  _highlightCache[key] = future;
  return future;
}

List<Map<String, String?>>? _highlightInBackground(
  Map<String, String> request,
) {
  final language = request['language'] ?? '';
  final mode = _languageMode(language);
  if (mode == null) return null;
  try {
    final highlighter = hl.Highlight()..registerLanguage(language, mode);
    final nodes =
        highlighter.parse(request['code'] ?? '', language: language).nodes;
    if (nodes == null) return null;
    final tokens = <Map<String, String?>>[];

    void append(String text, String? className) {
      if (text.isEmpty) return;
      if (tokens.isNotEmpty && tokens.last['class'] == className) {
        tokens.last['text'] = '${tokens.last['text']}$text';
      } else {
        tokens.add({'text': text, 'class': className});
      }
    }

    void flatten(hl.Node node, String? inheritedClass) {
      final className = node.className ?? inheritedClass;
      if (node.value case final value?) append(value, className);
      for (final child in node.children ?? const <hl.Node>[]) {
        flatten(child, className);
      }
    }

    for (final node in nodes) {
      flatten(node, null);
    }
    return tokens;
  } catch (_) {
    return null;
  }
}

TextStyle? _tokenStyle(BuildContext context, String? className) {
  if (className == null) return null;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final color = switch (className.split(' ').first) {
    'keyword' ||
    'selector-tag' ||
    'doctag' =>
      dark ? const Color(0xfff97583) : const Color(0xffd73a49),
    'title' ||
    'section' ||
    'type' =>
      dark ? const Color(0xffb392f0) : const Color(0xff6f42c1),
    'string' ||
    'regexp' ||
    'template-tag' =>
      dark ? const Color(0xff9ecbff) : const Color(0xff032f62),
    'number' ||
    'literal' ||
    'symbol' ||
    'bullet' =>
      dark ? const Color(0xff79b8ff) : const Color(0xff005cc5),
    'built_in' ||
    'attr' ||
    'attribute' =>
      dark ? const Color(0xff79b8ff) : const Color(0xff005cc5),
    'comment' ||
    'quote' =>
      dark ? const Color(0xff959da5) : const Color(0xff6a737d),
    'meta' ||
    'addition' =>
      dark ? const Color(0xff85e89d) : const Color(0xff22863a),
    'deletion' => dark ? const Color(0xffffab70) : const Color(0xffb31d28),
    'variable' ||
    'template-variable' =>
      dark ? const Color(0xffffab70) : const Color(0xffe36209),
    _ => null,
  };
  return color == null ? null : TextStyle(color: color);
}
