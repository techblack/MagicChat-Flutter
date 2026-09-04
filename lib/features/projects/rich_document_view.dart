import 'package:flutter/material.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import '../../domain/message_content.dart';

/// 将 Tiptap 协作正文的 XML block tree 渲染为 Flutter 原生控件。
///
/// 默认只负责展示，不直接修改 Yjs 状态；传入 [onEditText] 后，用户可以
/// 长按文本叶子交给上层编辑。来自 Web/Desktop 的 heading、列表、任务、
/// 表格和 marks 仍按 XML tree 原样渲染。
class RichDocumentView extends StatelessWidget {
  const RichDocumentView({required this.body, this.onEditText, super.key});

  final yjs.YXmlFragment body;
  final ValueChanged<yjs.YXmlText>? onEditText;

  @override
  Widget build(BuildContext context) {
    final children = _renderChildren(context, body);
    if (children.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
      children: children,
    );
  }

  List<Widget> _renderChildren(BuildContext context, yjs.YXmlFragment parent) {
    return parent
        .toArray()
        .map((node) => _renderNode(context, node))
        .whereType<Widget>()
        .toList(growable: false);
  }

  Widget? _renderNode(BuildContext context, Object? node) {
    if (node is yjs.YXmlText) {
      return _editableText(context, node);
    }
    if (node is! yjs.YXmlElement) return null;
    switch (node.name) {
      case 'paragraph':
        return _paragraph(context, node);
      case 'heading':
        return _heading(context, node);
      case 'bulletList':
        return _list(context, node, ordered: false);
      case 'orderedList':
        return _list(context, node, ordered: true);
      case 'taskList':
        return _list(context, node, task: true);
      case 'blockquote':
        return _blockquote(context, node);
      case 'codeBlock':
        return _codeBlock(context, node);
      case 'horizontalRule':
        return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8), child: Divider());
      case 'table':
        return _table(context, node);
      case 'documentImage':
      case 'image':
        return _image(context, node);
      case 'hardBreak':
        return const SizedBox(height: 8);
      case 'listItem':
      case 'taskItem':
        // These nodes are normally consumed by [_list]. Rendering them here
        // as a regular block keeps malformed/partial remote trees readable.
        return _listItem(context, node,
            ordered: false, index: 0, task: node.name == 'taskItem');
      default:
        return _fallback(context, node);
    }
  }

  Widget _paragraph(BuildContext context, yjs.YXmlElement node) {
    final textNodes = node.toArray().whereType<yjs.YXmlText>().toList();
    final content = textNodes.length == 1 && onEditText != null
        ? _editableText(context, textNodes.single)
        : Text.rich(_inlineSpan(context, node));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4), child: content);
  }

  Widget _heading(BuildContext context, yjs.YXmlElement node) {
    final level = (node.getAttribute('level') as num?)?.toInt() ?? 2;
    final style = switch (level) {
      1 => Theme.of(context).textTheme.headlineSmall,
      2 => Theme.of(context).textTheme.titleLarge,
      _ => Theme.of(context).textTheme.titleMedium,
    };
    final textNodes = node.toArray().whereType<yjs.YXmlText>().toList();
    final content = textNodes.length == 1 && onEditText != null
        ? _editableText(context, textNodes.single, style: style)
        : Text.rich(_inlineSpan(context, node), style: style);
    return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 5), child: content);
  }

  Widget _editableText(BuildContext context, yjs.YXmlText node,
      {TextStyle? style}) {
    final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(_inlineSpan(context, node), style: style));
    return onEditText == null
        ? content
        : InkWell(
            onLongPress: () => onEditText!(node),
            borderRadius: BorderRadius.circular(4),
            child: Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: '长按编辑文本块',
                child: content));
  }

  Widget _list(BuildContext context, yjs.YXmlElement node,
      {bool ordered = false, bool task = false}) {
    var index = 0;
    final items = node.toArray().whereType<yjs.YXmlElement>().map((item) {
      index += 1;
      return _listItem(context, item,
          ordered: ordered,
          index: index,
          task: task || item.name == 'taskItem');
    }).toList(growable: false);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: items));
  }

  Widget _listItem(BuildContext context, yjs.YXmlElement node,
      {required bool ordered, required int index, required bool task}) {
    final marker = task
        ? Checkbox(
            value: node.getAttribute('checked') == true,
            onChanged: null,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)
        : SizedBox(
            width: 24,
            child: Text(ordered ? '$index.' : '•',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge));
    final content = node
        .toArray()
        .map((child) {
          if (child is yjs.YXmlElement &&
              (child.name == 'bulletList' ||
                  child.name == 'orderedList' ||
                  child.name == 'taskList')) {
            return _renderNode(context, child)!;
          }
          if (child is yjs.YXmlElement) return _renderNode(context, child);
          return child is yjs.YXmlText
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text.rich(_inlineSpan(context, child)))
              : null;
        })
        .whereType<Widget>()
        .toList(growable: false);
    return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: task ? 32 : 26, child: marker),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content)),
        ]));
  }

  Widget _blockquote(BuildContext context, yjs.YXmlElement node) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
          border: Border(
              left: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 3))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _renderChildren(context, node)));

  Widget _codeBlock(BuildContext context, yjs.YXmlElement node) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: SelectableText(_plainText(node),
          style: const TextStyle(fontFamily: 'monospace')));

  Widget _table(BuildContext context, yjs.YXmlElement node) {
    final rows = node
        .toArray()
        .whereType<yjs.YXmlElement>()
        .where((row) => row.name == 'tableRow')
        .map((row) {
      final cells = row
          .toArray()
          .whereType<yjs.YXmlElement>()
          .where(
              (cell) => cell.name == 'tableCell' || cell.name == 'tableHeader')
          .map((cell) {
        final header = cell.name == 'tableHeader';
        return Container(
            padding: const EdgeInsets.all(8),
            color: header
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : null,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderChildren(context, cell)));
      }).toList(growable: false);
      return TableRow(children: cells);
    }).toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Table(
            border: TableBorder.all(
                color: Theme.of(context).colorScheme.outlineVariant),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows));
  }

  Widget _image(BuildContext context, yjs.YXmlElement node) {
    final external = node.getAttribute('externalUrl');
    final url = external is String ? parseExternalWebUri(external) : null;
    final alt = node.getAttribute('alt') is String
        ? (node.getAttribute('alt') as String).trim()
        : '';
    final fileId = node.getAttribute('fileId');
    final label = alt.isNotEmpty
        ? alt
        : fileId is String && fileId.isNotEmpty
            ? '图片：$fileId'
            : '图片';
    final width = (node.getAttribute('width') as num?)?.toDouble();
    final image = url == null
        ? _imagePlaceholder(context, label)
        : Image.network(url.toString(),
            width: width?.clamp(48, 640).toDouble(),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _imagePlaceholder(context, label));
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(label: label, image: true, child: image));
  }

  Widget _imagePlaceholder(BuildContext context, String label) => Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.image_outlined),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ]));

  Widget _fallback(BuildContext context, yjs.YXmlElement node) {
    final hasBlock = node.toArray().whereType<yjs.YXmlElement>().any((child) =>
        const {
          'paragraph',
          'heading',
          'bulletList',
          'orderedList',
          'taskList',
          'table'
        }.contains(child.name));
    if (hasBlock) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _renderChildren(context, node));
    }
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(_inlineSpan(context, node)));
  }

  InlineSpan _inlineSpan(BuildContext context, Object node) {
    if (node is yjs.YXmlText) {
      final spans = <InlineSpan>[];
      for (final op in node.toDelta()) {
        final value = _deltaText(op['insert']);
        if (value.isEmpty) continue;
        final attributes = op['attributes'];
        spans.add(TextSpan(
            text: value,
            style: _markStyle(
                context,
                attributes is Map
                    ? Map<String, Object?>.from(attributes)
                    : const {})));
      }
      return TextSpan(children: spans);
    }
    if (node is! yjs.YXmlFragment) return const TextSpan();
    final spans = <InlineSpan>[];
    for (final child in node.toArray()) {
      if (child is yjs.YXmlText) {
        spans.add(_inlineSpan(context, child));
      } else if (child is yjs.YXmlElement && child.name == 'hardBreak') {
        spans.add(const TextSpan(text: '\n'));
      } else if (child is yjs.YXmlFragment) {
        spans.add(_inlineSpan(context, child));
      }
    }
    return TextSpan(children: spans);
  }

  TextStyle _markStyle(BuildContext context, Map<String, Object?> marks) {
    Color? parseColor(Object? value) {
      if (value is! String) return null;
      var hex = value.trim().replaceFirst('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length != 8) return null;
      return Color(int.tryParse(hex, radix: 16) ?? 0);
    }

    final link = marks['link'];
    final linkAttrs = link is Map ? link : const <String, Object?>{};
    final decoration = marks['underline'] == true || link != null
        ? TextDecoration.underline
        : marks['strike'] == true
            ? TextDecoration.lineThrough
            : null;
    return TextStyle(
        fontWeight: marks['bold'] == true ? FontWeight.bold : null,
        fontStyle: marks['italic'] == true ? FontStyle.italic : null,
        decoration: decoration,
        fontFamily: marks['code'] == true ? 'monospace' : null,
        color: parseColor(marks['textStyle'] is Map
            ? (marks['textStyle'] as Map)['color']
            : marks['color']),
        backgroundColor: parseColor(marks['highlight'] is Map
            ? (marks['highlight'] as Map)['color']
            : marks['highlight']),
        shadows: linkAttrs['href'] is String
            ? [const Shadow(color: Colors.transparent)]
            : null);
  }

  String _deltaText(Object? value) {
    if (value is String) return value;
    if (value is Iterable) {
      return value.whereType<String>().join();
    }
    return '';
  }

  String _plainText(yjs.YXmlFragment node) => node.toArray().map((child) {
        if (child is yjs.YXmlText) return child.toString();
        if (child is yjs.YXmlFragment) return _plainText(child);
        return '';
      }).join();
}
