import 'package:flutter/material.dart';

/// Markdown 编辑器工具栏支持的最小操作集合。
///
/// 操作本身是纯文本转换，便于在协作会话和本机草稿两种编辑模式下复用。
enum MarkdownToolbarAction {
  bold,
  italic,
  strike,
  unorderedList,
  orderedList,
  taskList,
  link,
  image,
  divider,
  table,
}

/// 根据当前选区应用一个 Markdown 操作，并返回新的编辑器值。
TextEditingValue applyMarkdownToolbarAction(
    TextEditingValue value, MarkdownToolbarAction action) {
  final text = value.text;
  final selection = value.selection;
  final start = selection.start.clamp(0, text.length).toInt();
  final end = selection.end.clamp(start, text.length).toInt();
  final selected = text.substring(start, end);

  switch (action) {
    case MarkdownToolbarAction.bold:
      return _wrap(value, start, end, selected, '**', '**', '文本');
    case MarkdownToolbarAction.italic:
      return _wrap(value, start, end, selected, '_', '_', '文本');
    case MarkdownToolbarAction.strike:
      return _wrap(value, start, end, selected, '~~', '~~', '文本');
    case MarkdownToolbarAction.unorderedList:
      return _prefixLines(value, start, end, selected, '- ');
    case MarkdownToolbarAction.orderedList:
      return _prefixLines(value, start, end, selected, '1. ');
    case MarkdownToolbarAction.taskList:
      return _prefixLines(value, start, end, selected, '- [ ] ');
    case MarkdownToolbarAction.link:
      return _link(value, start, end, selected);
    case MarkdownToolbarAction.image:
      return _image(value, start, end, selected);
    case MarkdownToolbarAction.divider:
      return _insert(value, start, end, '\n\n---\n\n');
    case MarkdownToolbarAction.table:
      return _insert(value, start, end,
          '\n\n| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |\n\n');
  }
}

TextEditingValue _wrap(TextEditingValue value, int start, int end,
    String selected, String before, String after, String fallback) {
  final content = selected.isEmpty ? fallback : selected;
  final replacement = '$before$content$after';
  final selectionStart = start + before.length;
  final selectionEnd = selectionStart + content.length;
  return value.copyWith(
      text: value.text.replaceRange(start, end, replacement),
      selection:
          TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd),
      composing: TextRange.empty);
}

TextEditingValue _prefixLines(TextEditingValue value, int start, int end,
    String selected, String prefix) {
  final lineStart = value.text.lastIndexOf('\n', start - 1) + 1;
  final lineEnd = value.text.indexOf('\n', end);
  final lineEndExclusive = lineEnd == -1 ? value.text.length : lineEnd;
  final content = value.text.substring(lineStart, lineEndExclusive);
  final source = content.isEmpty ? '列表项' : content;
  final lines = source.split('\n').map((line) => '$prefix$line').join('\n');
  final replacement = lines;
  final selectionStart = lineStart + (start - lineStart) + prefix.length;
  final selectedEnd =
      lineStart + (end - lineStart) + (lines.length - source.length);
  final selectionEnd = selected.isEmpty
      ? (content.isEmpty ? selectionStart + '列表项'.length : selectionStart)
      : selectedEnd;
  return value.copyWith(
      text: value.text.replaceRange(lineStart, lineEndExclusive, replacement),
      selection:
          TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd),
      composing: TextRange.empty);
}

TextEditingValue _link(
    TextEditingValue value, int start, int end, String selected) {
  final label = selected.isEmpty ? '链接文字' : selected;
  final replacement = '[$label](https://example.com)';
  final urlStart = start + label.length + 3;
  return value.copyWith(
      text: value.text.replaceRange(start, end, replacement),
      selection:
          TextSelection(baseOffset: urlStart, extentOffset: urlStart + 19),
      composing: TextRange.empty);
}

TextEditingValue _image(
    TextEditingValue value, int start, int end, String selected) {
  final alt = selected.isEmpty ? '图片描述' : selected;
  final replacement = '![$alt](https://example.com/image.png)';
  final urlStart = start + alt.length + 4;
  return value.copyWith(
      text: value.text.replaceRange(start, end, replacement),
      selection:
          TextSelection(baseOffset: urlStart, extentOffset: urlStart + 29),
      composing: TextRange.empty);
}

TextEditingValue _insert(
    TextEditingValue value, int start, int end, String replacement) {
  final cursor = start + replacement.length;
  return value.copyWith(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty);
}

class MarkdownEditorToolbar extends StatelessWidget {
  const MarkdownEditorToolbar({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  void _apply(MarkdownToolbarAction action) {
    controller.value = applyMarkdownToolbarAction(controller.value, action);
    onChanged(controller.text);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Markdown 格式工具栏',
        child: SizedBox(
          height: 48,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _tool(context, Icons.format_bold, '粗体',
                      MarkdownToolbarAction.bold),
                  _tool(context, Icons.format_italic, '斜体',
                      MarkdownToolbarAction.italic),
                  _tool(context, Icons.strikethrough_s, '删除线',
                      MarkdownToolbarAction.strike),
                  const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                  _tool(context, Icons.format_list_bulleted, '无序列表',
                      MarkdownToolbarAction.unorderedList),
                  _tool(context, Icons.format_list_numbered, '有序列表',
                      MarkdownToolbarAction.orderedList),
                  _tool(context, Icons.checklist, '任务列表',
                      MarkdownToolbarAction.taskList),
                  const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                  _tool(context, Icons.link, '链接', MarkdownToolbarAction.link),
                  _tool(context, Icons.image_outlined, '图片',
                      MarkdownToolbarAction.image),
                  _tool(context, Icons.horizontal_rule, '分割线',
                      MarkdownToolbarAction.divider),
                  _tool(context, Icons.table_chart_outlined, '表格',
                      MarkdownToolbarAction.table),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _tool(BuildContext context, IconData icon, String label,
          MarkdownToolbarAction action) =>
      IconButton(
        tooltip: label,
        onPressed: enabled ? () => _apply(action) : null,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
      );
}
