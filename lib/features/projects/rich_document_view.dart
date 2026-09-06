import 'package:flutter/material.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import '../../domain/message_content.dart';
import 'rich_document_block_background.dart';

/// 将 Tiptap 协作正文的 XML block tree 渲染为 Flutter 原生控件。
///
/// 默认只负责展示，不直接修改 Yjs 状态；传入 [onSelectText] 和
/// [onTextChanged] 后，用户可以点击文本叶子原位编辑。长按回调继续作为
/// 完整文本对话框的辅助入口。来自 Web/Desktop 的 heading、列表、任务、
/// 表格和 marks 仍按 XML tree 原样渲染。
class RichDocumentView extends StatelessWidget {
  const RichDocumentView({
    required this.body,
    this.selectedText,
    this.onSelectText,
    this.onTextChanged,
    this.onEditText,
    this.imageUrlResolver,
    this.onEditImage,
    super.key,
  });

  final yjs.YXmlFragment body;
  final yjs.YXmlText? selectedText;
  final ValueChanged<yjs.YXmlText?>? onSelectText;
  final void Function(yjs.YXmlText node, String value)? onTextChanged;
  final ValueChanged<yjs.YXmlText>? onEditText;
  final Future<Uri?> Function(String fileId)? imageUrlResolver;
  final ValueChanged<yjs.YXmlElement>? onEditImage;

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
        return _withBlockBackground(node, _paragraph(context, node));
      case 'heading':
        return _withBlockBackground(node, _heading(context, node));
      case 'bulletList':
        return _withBlockBackground(node, _list(context, node, ordered: false));
      case 'orderedList':
        return _withBlockBackground(node, _list(context, node, ordered: true));
      case 'taskList':
        return _withBlockBackground(node, _list(context, node, task: true));
      case 'blockquote':
        return _withBlockBackground(node, _blockquote(context, node));
      case 'codeBlock':
        return _withBlockBackground(node, _codeBlock(context, node));
      case 'horizontalRule':
        return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8), child: Divider());
      case 'table':
        return _withBlockBackground(node, _table(context, node));
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

  Widget _withBlockBackground(yjs.YXmlElement node, Widget child) {
    final color = richDocumentBlockBackgroundDisplayColor(
        node.getAttribute('blockBackgroundColor'));
    return color == null
        ? child
        : RichDocumentBlockBackground(color: color, child: child);
  }

  Widget _paragraph(BuildContext context, yjs.YXmlElement node) {
    final textNodes = node.toArray().whereType<yjs.YXmlText>().toList();
    final textAlign = _textAlign(node);
    final content =
        textNodes.length == 1 && (onEditText != null || onSelectText != null)
            ? _editableText(context, textNodes.single, textAlign: textAlign)
            : Text.rich(_inlineSpan(context, node), textAlign: textAlign);
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
    final textAlign = _textAlign(node);
    final content =
        textNodes.length == 1 && (onEditText != null || onSelectText != null)
            ? _editableText(context, textNodes.single,
                style: style, textAlign: textAlign)
            : Text.rich(_inlineSpan(context, node),
                style: style, textAlign: textAlign);
    return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 5), child: content);
  }

  Widget _editableText(BuildContext context, yjs.YXmlText node,
      {TextStyle? style, TextAlign textAlign = TextAlign.left}) {
    if (identical(selectedText, node) && onTextChanged != null) {
      final markStyle = _markStyle(context, _marks(node));
      return Container(
        key: const ValueKey('rich-document-inline-editor'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: .28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: .55)),
        ),
        child: TextFormField(
          key: ObjectKey(node),
          initialValue: node.toString(),
          autofocus: true,
          minLines: 1,
          maxLines: null,
          style: style?.merge(markStyle) ?? markStyle,
          textAlign: textAlign,
          onChanged: (value) => onTextChanged!(node, value),
          decoration: const InputDecoration(
              border: InputBorder.none, isDense: true, hintText: '输入正文'),
        ),
      );
    }
    final value = node.toString();
    final content = Container(
      constraints: const BoxConstraints(minHeight: 28),
      alignment: switch (textAlign) {
        TextAlign.center => Alignment.center,
        TextAlign.right => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: value.isEmpty
          ? Text('点击输入正文',
              textAlign: textAlign,
              style: (style ?? Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))
          : Text.rich(_inlineSpan(context, node),
              style: style, textAlign: textAlign),
    );
    if (onEditText == null && onSelectText == null) return content;
    final editor = InkWell(
      onTap: onSelectText == null ? null : () => onSelectText!(node),
      onLongPress: onEditText == null ? null : () => onEditText!(node),
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
    return onSelectText == null
        ? Tooltip(message: '长按编辑文本块', child: editor)
        : Semantics(button: true, label: '点击原位编辑', child: editor);
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

  Widget _codeBlock(BuildContext context, yjs.YXmlElement node) {
    final textNodes = node.toArray().whereType<yjs.YXmlText>().toList();
    final content =
        textNodes.length == 1 && (onSelectText != null || onEditText != null)
            ? _editableText(context, textNodes.single,
                style: const TextStyle(fontFamily: 'monospace'))
            : SelectableText(_plainText(node),
                style: const TextStyle(fontFamily: 'monospace'));
    return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8)),
        child: content);
  }

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
    final externalUrl =
        external is String ? parseExternalWebUri(external) : null;
    final url = externalUrl?.scheme == 'https' ? externalUrl : null;
    final rawFileId = node.getAttribute('fileId');
    final fileId = rawFileId is String && rawFileId.trim().isNotEmpty
        ? rawFileId.trim()
        : null;
    final alt = node.getAttribute('alt') is String
        ? (node.getAttribute('alt') as String).trim()
        : '';
    final label = alt.isNotEmpty ? alt : '图片';
    final rawWidth = node.getAttribute('width');
    final width =
        rawWidth is num ? ((rawWidth / 5).round() * 5).clamp(20, 100) : 100;
    final alignment = switch (node.getAttribute('alignment')) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };
    Widget source(Uri? value) => value == null
        ? _imagePlaceholder(context, label)
        : Image.network(value.toString(),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _imagePlaceholder(context, label));
    final image = url != null
        ? source(url)
        : fileId != null && imageUrlResolver != null
            ? FutureBuilder<Uri?>(
                future: imageUrlResolver!(fileId),
                builder: (context, snapshot) =>
                    snapshot.connectionState == ConnectionState.waiting &&
                            !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : source(snapshot.data))
            : source(null);
    final content = LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: alignment,
        child: SizedBox(
          key: ValueKey(
              'rich-document-image-frame-${fileId ?? external ?? 'empty'}'),
          width: constraints.maxWidth * width / 100,
          child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72), child: image),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        label: onEditImage == null ? label : '设置图片：$label',
        image: true,
        button: onEditImage != null,
        child: InkWell(
          key: ValueKey('rich-document-image-${fileId ?? external ?? 'empty'}'),
          onTap: onEditImage == null ? null : () => onEditImage!(node),
          borderRadius: BorderRadius.circular(10),
          child: content,
        ),
      ),
    );
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

  Map<String, Object?> _marks(yjs.YXmlText node) {
    final delta = node.toDelta();
    if (delta.isEmpty) return const {};
    final attributes = delta.first['attributes'];
    return attributes is Map ? Map<String, Object?>.from(attributes) : const {};
  }

  TextAlign _textAlign(yjs.YXmlElement node) =>
      switch (node.getAttribute('textAlign')) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      };

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
