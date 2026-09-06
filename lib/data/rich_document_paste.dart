import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import '../domain/rich_document_format.dart';

typedef RichDocumentClipboardContent = ({String? html, String? text});

class RichDocumentPaste {
  const RichDocumentPaste(this.blocks, this.firstText);

  final List<yjs.YXmlElement> blocks;
  final yjs.YXmlText? firstText;
}

Future<RichDocumentClipboardContent?> readRichDocumentClipboard() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  return readRichDocumentClipboardReader(await clipboard.read());
}

Future<RichDocumentClipboardContent?> readRichDocumentClipboardReader(
    ClipboardDataReader reader) async {
  final html = reader.canProvide(Formats.htmlText)
      ? await reader.readValue(Formats.htmlText)
      : null;
  final text = reader.canProvide(Formats.plainText)
      ? await reader.readValue(Formats.plainText)
      : null;
  if ((html == null || html.trim().isEmpty) && (text == null || text.isEmpty)) {
    return null;
  }
  return (html: html, text: text);
}

RichDocumentPaste parseRichDocumentPaste(RichDocumentClipboardContent content) {
  final html = content.html?.trim();
  if (html != null && html.isNotEmpty) return _parseHtml(html);
  final text = content.text ?? '';
  if (_looksLikeHtml(text)) return _parseHtml(text);
  final blocks = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => _textBlock('paragraph', line))
      .toList(growable: false);
  return RichDocumentPaste(blocks, _firstXmlText(blocks));
}

const _discardedTags = {
  'button',
  'canvas',
  'col',
  'colgroup',
  'embed',
  'form',
  'iframe',
  'input',
  'link',
  'math',
  'meta',
  'noscript',
  'object',
  'option',
  'script',
  'select',
  'style',
  'svg',
  'textarea',
};

const _blockTags = {
  'article',
  'blockquote',
  'div',
  'figure',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'img',
  'li',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'ul',
};

const _inlineTags = {
  'a',
  'b',
  'br',
  'code',
  'del',
  'em',
  'i',
  'mark',
  's',
  'span',
  'strike',
  'strong',
  'u',
};

RichDocumentPaste _parseHtml(String value) {
  final document = html_parser.parse(value);
  final blocks = _parseBlocks(document.body?.nodes ?? const []);
  return RichDocumentPaste(blocks, _firstXmlText(blocks));
}

List<yjs.YXmlElement> _parseBlocks(Iterable<dom.Node> nodes) {
  final blocks = <yjs.YXmlElement>[];
  final inline = <dom.Node>[];

  void flushInline() {
    final paragraph = _inlineBlock('paragraph', inline);
    inline.clear();
    if (paragraph != null) blocks.add(paragraph);
  }

  for (final node in nodes) {
    if (node is dom.Comment) continue;
    if (node is! dom.Element) {
      inline.add(node);
      continue;
    }
    final tag = node.localName;
    if (_discardedTags.contains(tag)) continue;
    if (!_blockTags.contains(tag)) {
      if (_hasBlockChildren(node)) {
        flushInline();
        blocks.addAll(_parseBlocks(node.nodes));
      } else {
        inline.add(node);
      }
      continue;
    }
    flushInline();
    blocks.addAll(_parseBlock(node));
  }
  flushInline();
  return blocks;
}

List<yjs.YXmlElement> _parseBlock(dom.Element element) {
  final tag = element.localName ?? '';
  if (tag == 'div' || tag == 'article' || tag == 'section') {
    if (_hasBlockChildren(element) || _isInsideTaskItem(element)) {
      return _parseBlocks(element.nodes);
    }
    final paragraph = _inlineBlock('paragraph', element.nodes,
        alignment: _alignment(element),
        inheritedMarks: _presentationMarks(element, const {}));
    return paragraph == null ? const [] : [paragraph];
  }
  if (tag == 'p' || RegExp(r'^h[1-6]$').hasMatch(tag)) {
    final name = tag == 'p' ? 'paragraph' : 'heading';
    final block = _inlineBlock(name, element.nodes,
        alignment: _alignment(element),
        inheritedMarks: _presentationMarks(element, const {}));
    if (block == null) return const [];
    if (name == 'heading') {
      block.setAttribute(
          'level', int.parse(tag.substring(1)).clamp(1, 3).toInt());
    }
    return [block];
  }
  if (tag == 'blockquote') {
    final children = _parseBlocks(element.nodes);
    if (children.isEmpty) return const [];
    final block = yjs.YXmlElement('blockquote')..insert(0, children);
    return [block];
  }
  if (tag == 'pre') {
    final value = element.text;
    return [_textBlock('codeBlock', value)];
  }
  if (tag == 'ul' || tag == 'ol') return [_parseList(element)];
  if (tag == 'table') {
    final table = _parseTable(element);
    return table == null ? _parseTableFallback(element) : [table];
  }
  if (tag == 'hr') return [_parseHorizontalRule(element)];
  if (tag == 'figure') {
    final image = _parseDocumentImage(element);
    return image == null ? _parseBlocks(element.nodes) : [image];
  }
  if (tag == 'img') {
    final image = _parseImage(element);
    return image == null ? const [] : [image];
  }
  if (tag == 'li') {
    final paragraph = _inlineBlock('paragraph', element.nodes);
    return paragraph == null ? const [] : [paragraph];
  }
  return _parseBlocks(element.nodes);
}

yjs.YXmlElement? _inlineBlock(String name, Iterable<dom.Node> nodes,
    {String? alignment, Map<String, Object?> inheritedMarks = const {}}) {
  final content = _InlineContent();
  for (final node in nodes) {
    _appendInline(content, node, inheritedMarks);
  }
  final text = content.toXmlText();
  if (text == null) return null;
  final block = yjs.YXmlElement(name)..insert(0, [text]);
  if (alignment != null && alignment != 'left') {
    block.setAttribute('textAlign', alignment);
  }
  return block;
}

void _appendInline(
    _InlineContent target, dom.Node node, Map<String, Object?> inheritedMarks) {
  if (node is dom.Text) {
    target.add(node.data.replaceAll('\u00a0', ' '), inheritedMarks);
    return;
  }
  if (node is! dom.Element || _discardedTags.contains(node.localName)) return;
  if (node.localName == 'br') {
    target.add('\n', inheritedMarks, collapseWhitespace: false);
    return;
  }
  if (_blockTags.contains(node.localName)) return;
  if (!_inlineTags.contains(node.localName)) {
    for (final child in node.nodes) {
      _appendInline(target, child, inheritedMarks);
    }
    return;
  }
  final marks = _presentationMarks(node, inheritedMarks);
  for (final child in node.nodes) {
    _appendInline(target, child, marks);
  }
}

class _InlineContent {
  final List<_InlineSegment> _segments = [];

  void add(String value, Map<String, Object?> marks,
      {bool collapseWhitespace = true}) {
    final text = collapseWhitespace
        ? value.replaceAll(RegExp(r'[\t\n\f\r ]+'), ' ')
        : value;
    if (text.isEmpty) return;
    _segments.add(_InlineSegment(text, Map.of(marks)));
  }

  yjs.YXmlText? toXmlText() {
    while (_segments.isNotEmpty && _segments.first.text.trimLeft().isEmpty) {
      _segments.removeAt(0);
    }
    while (_segments.isNotEmpty && _segments.last.text.trimRight().isEmpty) {
      _segments.removeLast();
    }
    if (_segments.isEmpty) return null;
    _segments.first.text = _segments.first.text.trimLeft();
    _segments.last.text = _segments.last.text.trimRight();
    final text = yjs.YXmlText();
    for (final segment in _segments) {
      if (segment.text.isNotEmpty) {
        text.insert(text.length, segment.text,
            segment.marks.isEmpty ? null : segment.marks);
      }
    }
    return text.length == 0 ? null : text;
  }
}

class _InlineSegment {
  _InlineSegment(this.text, this.marks);

  String text;
  final Map<String, Object?> marks;
}

Map<String, Object?> _presentationMarks(
    dom.Element node, Map<String, Object?> inheritedMarks) {
  final marks = Map<String, Object?>.from(inheritedMarks);
  final style = _styles(node);
  switch (node.localName) {
    case 'strong':
    case 'b':
      marks['bold'] = true;
      break;
    case 'em':
    case 'i':
      marks['italic'] = true;
      break;
    case 'u':
      marks['underline'] = true;
      break;
    case 's':
    case 'del':
    case 'strike':
      marks['strike'] = true;
      break;
    case 'code':
      marks['code'] = true;
      break;
    case 'a':
      final href = _safeLink(node.attributes['href']);
      if (href != null) marks['link'] = {'href': href};
      break;
    case 'mark':
      final color = _safeColor(
          node.attributes['data-color'] ?? style['background-color']);
      if (color != null) marks['highlight'] = {'color': color};
      break;
    case 'span':
      final color = _safeColor(style['color']);
      if (color != null) marks['textStyle'] = {'color': color};
      break;
  }
  final weight = int.tryParse(style['font-weight'] ?? '');
  if (style['font-weight'] == 'bold' ||
      style['font-weight'] == 'bolder' ||
      (weight != null && weight >= 600)) {
    marks['bold'] = true;
  }
  if (style['font-style'] == 'italic') marks['italic'] = true;
  final decoration =
      '${style['text-decoration-line'] ?? ''} ${style['text-decoration'] ?? ''}';
  if (decoration.contains('underline')) marks['underline'] = true;
  if (decoration.contains('line-through')) marks['strike'] = true;
  final background = _safeColor(style['background-color']);
  if (background != null) marks['highlight'] = {'color': background};
  final color = _safeColor(style['color']);
  if (color != null) marks['textStyle'] = {'color': color};
  return marks;
}

yjs.YXmlElement _parseList(dom.Element element) {
  final task = element.localName == 'ul' &&
      element.attributes['data-type'] == 'taskList';
  final list = yjs.YXmlElement(task
      ? 'taskList'
      : element.localName == 'ol'
          ? 'orderedList'
          : 'bulletList');
  if (element.localName == 'ol') {
    final start = _integer(element.attributes['start'], 1, 10000);
    if (start != null && start != 1) list.setAttribute('start', start);
  }
  final items = <yjs.YXmlElement>[];
  for (final child
      in element.children.where((child) => child.localName == 'li')) {
    final item = yjs.YXmlElement(task ? 'taskItem' : 'listItem');
    if (task) {
      item.setAttribute(
          'checked',
          child.attributes['data-checked'] == '' ||
              child.attributes['data-checked'] == 'true');
    }
    final blocks = _parseBlocks(child.nodes);
    item.insert(0, blocks.isEmpty ? [_textBlock('paragraph', '')] : blocks);
    items.add(item);
  }
  if (items.isEmpty) {
    items.add(yjs.YXmlElement(task ? 'taskItem' : 'listItem')
      ..insert(0, [_textBlock('paragraph', '')]));
  }
  list.insert(0, items);
  return list;
}

yjs.YXmlElement? _parseTable(dom.Element element) {
  final sourceRows = _sourceTableRows(element);
  if (sourceRows.isEmpty) return null;
  final sourceCells = sourceRows
      .map((row) => row.children
          .where((cell) => cell.localName == 'td' || cell.localName == 'th')
          .toList(growable: false))
      .toList(growable: false);
  final columnCount = sourceCells.first.length;
  if (columnCount == 0 ||
      sourceCells.any((cells) => cells.length != columnCount)) {
    return null;
  }
  final rows = <yjs.YXmlElement>[];
  for (var rowIndex = 0; rowIndex < sourceRows.length; rowIndex++) {
    final row = yjs.YXmlElement('tableRow');
    final cells = <yjs.YXmlElement>[];
    for (final source in sourceCells[rowIndex]) {
      final cell = yjs.YXmlElement(rowIndex == 0 || source.localName == 'th'
          ? 'tableHeader'
          : 'tableCell');
      final colspan = _integer(source.attributes['colspan'], 1, 100) ?? 1;
      final rowspan = _integer(source.attributes['rowspan'], 1, 100) ?? 1;
      if (colspan != 1) cell.setAttribute('colspan', colspan);
      if (rowspan != 1) cell.setAttribute('rowspan', rowspan);
      final colwidth = _columnWidths(
          source.attributes['colwidth'] ?? source.attributes['data-colwidth'],
          colspan);
      if (colwidth != null) cell.setAttribute('colwidth', colwidth);
      final blocks = _parseBlocks(source.nodes);
      cell.insert(0, blocks.isEmpty ? [_textBlock('paragraph', '')] : blocks);
      cells.add(cell);
    }
    row.insert(0, cells);
    rows.add(row);
  }
  if (rows.isEmpty) return null;
  return yjs.YXmlElement('table')..insert(0, rows);
}

List<dom.Element> _sourceTableRows(dom.Element table) {
  final rows = <dom.Element>[];
  for (final child in table.children) {
    if (child.localName == 'tr') {
      rows.add(child);
    } else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName)) {
      rows.addAll(child.children.where((row) => row.localName == 'tr'));
    }
  }
  return rows;
}

List<yjs.YXmlElement> _parseTableFallback(dom.Element table) =>
    _sourceTableRows(table)
        .expand((row) => row.children
            .where((cell) => cell.localName == 'td' || cell.localName == 'th'))
        .expand((cell) => _parseBlocks(cell.nodes))
        .toList(growable: false);

yjs.YXmlElement _parseHorizontalRule(dom.Element element) {
  final thickness = _integer(element.attributes['data-thickness'], 1, 6) ?? 1;
  final style = const {'dashed', 'dotted', 'double', 'solid'}
          .contains(element.attributes['data-line-style'])
      ? element.attributes['data-line-style']!
      : 'solid';
  return yjs.YXmlElement('horizontalRule')
    ..setAttribute('lineStyle', style)
    ..setAttribute('thickness', thickness);
}

yjs.YXmlElement? _parseDocumentImage(dom.Element element) {
  if (!element.attributes.containsKey('data-document-image')) return null;
  return _documentImage(
    externalUrl: element.attributes['data-external-url'],
    fileId: element.attributes['data-file-id'],
    alt: element.attributes['data-alt'],
    alignment: element.attributes['data-alignment'],
    width: element.attributes['data-width'],
    allowEmpty: true,
  );
}

yjs.YXmlElement? _parseImage(dom.Element element) => _documentImage(
      externalUrl: element.attributes['src'],
      alt: element.attributes['alt'],
    );

yjs.YXmlElement? _documentImage({
  String? externalUrl,
  String? fileId,
  String? alt,
  String? alignment,
  String? width,
  bool allowEmpty = false,
}) {
  final safeUrl = _safeImageUrl(externalUrl);
  final safeFileId =
      fileId != null && RegExp(r'^[\w-]{1,200}$').hasMatch(fileId)
          ? fileId
          : null;
  if (!allowEmpty && safeUrl == null && safeFileId == null) return null;
  final parsedWidth = _integer(width, 20, 100) ?? 100;
  final safeAlt = alt ?? '';
  final image = yjs.YXmlElement('documentImage')
    ..setAttribute('alignment',
        alignment == 'left' || alignment == 'right' ? alignment! : 'center')
    ..setAttribute(
        'alt', safeAlt.length > 500 ? safeAlt.substring(0, 500) : safeAlt)
    ..setAttribute('width', (parsedWidth / 5).round() * 5);
  if (safeUrl != null) image.setAttribute('externalUrl', safeUrl);
  if (safeFileId != null) image.setAttribute('fileId', safeFileId);
  return image;
}

yjs.YXmlElement _textBlock(String name, String value) {
  final text = yjs.YXmlText();
  if (value.isNotEmpty) text.insert(0, value);
  return yjs.YXmlElement(name)..insert(0, [text]);
}

yjs.YXmlText? _firstXmlText(Iterable<Object?> nodes) {
  for (final node in nodes) {
    if (node is yjs.YXmlText) return node;
    if (node is yjs.YXmlFragment) {
      final text = _firstXmlText(node.toArray());
      if (text != null) return text;
    }
  }
  return null;
}

bool _hasBlockChildren(dom.Element element) =>
    element.children.any((child) => _blockTags.contains(child.localName));

bool _isInsideTaskItem(dom.Element element) {
  dom.Node? current = element.parentNode;
  while (current is dom.Element) {
    if (current.localName == 'li' &&
        current.attributes['data-type'] == 'taskItem') {
      return true;
    }
    current = current.parentNode;
  }
  return false;
}

Map<String, String> _styles(dom.Element element) {
  final styles = <String, String>{};
  for (final declaration in (element.attributes['style'] ?? '').split(';')) {
    final separator = declaration.indexOf(':');
    if (separator < 0) continue;
    styles[declaration.substring(0, separator).trim().toLowerCase()] =
        declaration.substring(separator + 1).trim().toLowerCase();
  }
  return styles;
}

String? _alignment(dom.Element element) {
  final value = _styles(element)['text-align'] ?? element.attributes['align'];
  return const {'left', 'center', 'right'}.contains(value) ? value : null;
}

String? _safeColor(String? value) {
  if (value == null) return null;
  final normalized =
      value.trim().replaceFirst(RegExp(r'\s*!important\s*$'), '');
  return richDocumentBlockBackgroundColors
          .any((color) => color.value == normalized)
      ? normalized
      : null;
}

String? _safeLink(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  return uri != null &&
          const {'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)
      ? uri.toString()
      : null;
}

String? _safeImageUrl(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
      ? uri.toString()
      : null;
}

int? _integer(String? value, int min, int max) {
  if (value == null || !RegExp(r'^\d+$').hasMatch(value)) return null;
  final parsed = int.parse(value);
  return parsed >= min && parsed <= max ? parsed : null;
}

List<int>? _columnWidths(String? value, int colspan) {
  if (value == null) return null;
  final widths = value
      .split(',')
      .map((width) => _integer(width.trim(), 20, 2000))
      .toList(growable: false);
  return widths.length == colspan && widths.every((width) => width != null)
      ? widths.cast<int>()
      : null;
}

bool _looksLikeHtml(String value) => RegExp(
      r'<\s*(?:!doctype|html|body|p|h[1-6]|ul|ol|li|table|blockquote|pre|div|section|article|figure|img|hr)\b',
      caseSensitive: false,
    ).hasMatch(value);
