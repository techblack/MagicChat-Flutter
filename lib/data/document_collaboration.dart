import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import 'document_realtime.dart';

enum DocumentCollaborationStatus { disconnected, connecting, synced, error }

/// Flutter 富文档目前开放的安全 block 追加操作。
///
/// 这些操作只会在 `body` 末尾插入新节点，不重写已有 XML tree，因此不会
/// 破坏来自 Web/Desktop 的图片、表格或文字 marks。
enum RichDocumentBlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  bulletList,
  orderedList,
  taskList,
  blockquote,
  codeBlock,
}

typedef RichDocumentImageAttributes = ({
  String alignment,
  String alt,
  String? externalUrl,
  String? fileId,
  int width,
});

/// 将协作文档绑定到服务端 Yjs 类型，并通过 Hocuspocus sync 帧交换更新。
///
/// Markdown 使用服务端约定的 `Y.Text("markdown")`。富文档使用服务端约定的
/// `Y.XmlFragment("body")`，正文使用标准的 XML Element/Text 子节点写入，
/// 与 Tiptap Collaboration 的 block tree 共用同一持久化状态。
class DocumentCollaborationSession extends ChangeNotifier {
  DocumentCollaborationSession({
    required String serverUrl,
    required String token,
    required this.documentId,
    required this.documentType,
    required DocumentSocketConnector connector,
  })  : _realtime = DocumentRealtime(
          serverUrl: serverUrl,
          token: token,
          documentId: documentId,
          connector: connector,
        ),
        _document = yjs.Doc(yjs.DocOpts(guid: documentId)) {
    _awareness = yjs.Awareness(_document);
    _markdown = _document.getText('markdown')!;
    _body = _document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
    _undoManager = documentType == 'document'
        ? yjs.UndoManager(_body, yjs.UndoManagerOpts(captureTimeout: 500))
        : null;
  }

  final String documentId;
  final String documentType;
  final DocumentRealtime _realtime;
  final yjs.Doc _document;
  late final yjs.Awareness _awareness;
  late final yjs.YText _markdown;
  late final yjs.YXmlFragment _body;
  late final yjs.UndoManager? _undoManager;
  StreamSubscription<Uint8List>? _subscription;
  DocumentCollaborationStatus status = DocumentCollaborationStatus.disconnected;
  bool _closed = false;
  bool _authenticated = false;
  bool _handlersAttached = false;

  /// 当前文档的共享富文档根节点，便于后续接入 XML block 编辑器。
  yjs.YXmlFragment get body => _body;

  String get text =>
      documentType == 'markdown' ? _markdown.toString() : _readBodyText();

  /// 当前连接中除本机外的在线协作者数量。
  int get collaboratorCount => _awareness.states.keys
      .where((client) => client != _awareness.clientID)
      .length;

  /// 当前 Awareness 状态，供编辑器展示用户信息或光标扩展使用。
  Map<int, Map<String, Object?>> get awarenessStates =>
      Map.unmodifiable(_awareness.states);

  bool get canUndo => _undoManager?.canUndo() ?? false;
  bool get canRedo => _undoManager?.canRedo() ?? false;

  void stopUndoCapture() => _undoManager?.stopCapturing();

  bool undo() {
    if (status != DocumentCollaborationStatus.synced || !canUndo) return false;
    _undoManager!.stopCapturing();
    final changed = _undoManager.undo() != null;
    if (changed) notifyListeners();
    return changed;
  }

  bool redo() {
    if (status != DocumentCollaborationStatus.synced || !canRedo) return false;
    _undoManager!.stopCapturing();
    final changed = _undoManager.redo() != null;
    if (changed) notifyListeners();
    return changed;
  }

  void setPresence(Map<String, Object?> state) {
    if (_closed) return;
    _awareness.setLocalState(state);
  }

  Future<void> connect() async {
    _closed = false;
    _authenticated = false;
    status = DocumentCollaborationStatus.connecting;
    notifyListeners();
    if (!_handlersAttached) {
      _document.on('update', _onDocumentUpdate);
      _awareness.on('update', _onAwarenessUpdate);
      _handlersAttached = true;
    }
    await _subscription?.cancel();
    _subscription = _realtime.events.listen(_onFrame, onError: (_) {
      _markError();
    }, onDone: _markError);
    try {
      await _realtime.connect();
    } catch (_) {
      status = DocumentCollaborationStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  /// 重新建立 WebSocket/Hocuspocus 连接，保留当前 Yjs 文档和编辑状态。
  Future<void> reconnect() async {
    if (_closed) return;
    await connect();
  }

  void replaceText(String value) {
    if (status != DocumentCollaborationStatus.synced || value == text) {
      return;
    }
    final oldText = text;
    final isolateUndo = _isBulkTextChange(oldText, value);
    if (isolateUndo) _undoManager?.stopCapturing();
    _document.transact((_) {
      if (documentType == 'markdown') {
        _replaceTextRange(_markdown, oldText, value);
      } else {
        _replaceBodyText(value);
      }
    });
    if (isolateUndo) _undoManager?.stopCapturing();
  }

  /// 更新一个已有的 XML 文本叶子，保留该叶子的 marks 属性。
  void replaceXmlText(yjs.YXmlText node, String value,
      {Map<String, Object?>? marks}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return;
    }
    final nextMarks = marks ?? _marksFor(node);
    final current = node.toString();
    final currentMarks = _marksFor(node);
    if (current == value && mapEquals(currentMarks, nextMarks)) {
      return;
    }
    final sameMarks = mapEquals(currentMarks, nextMarks);
    final isolateUndo = !sameMarks || _isBulkTextChange(current, value);
    if (isolateUndo) _undoManager?.stopCapturing();
    _document.transact((_) {
      if (sameMarks) {
        _replaceTextRange(node, current, value, attributes: nextMarks);
      } else {
        _clearText(node);
        if (value.isNotEmpty) node.insert(0, value, nextMarks);
      }
    });
    if (isolateUndo) _undoManager?.stopCapturing();
    notifyListeners();
  }

  /// 返回当前文本叶子的可见 marks，供编辑器初始化格式控件。
  Map<String, Object?> xmlTextMarks(yjs.YXmlText node) => _marksFor(node);

  /// 返回可直接转换的顶层文本块类型；列表、表格等复合结构保持原样。
  RichDocumentBlockType? xmlTextBlockType(yjs.YXmlText node) {
    final block = _topLevelBlock(node);
    if (block == null || !identical(block.parent, _body)) return null;
    return switch (block.name) {
      'paragraph' => RichDocumentBlockType.paragraph,
      'heading' => switch ((block.getAttribute('level') as num?)?.toInt()) {
          1 => RichDocumentBlockType.heading1,
          3 => RichDocumentBlockType.heading3,
          _ => RichDocumentBlockType.heading2,
        },
      'codeBlock' => RichDocumentBlockType.codeBlock,
      _ => null,
    };
  }

  /// 返回段落或标题的对齐方式，未设置时按 Tiptap 默认左对齐。
  String xmlTextAlignment(yjs.YXmlText node) {
    final block = _textAlignmentBlock(node);
    final value = block?.getAttribute('textAlign');
    return value == 'center' || value == 'right' ? value as String : 'left';
  }

  /// 更新段落或标题对齐；左对齐会移除默认属性，保持文档结构精简。
  bool setXmlTextAlignment(yjs.YXmlText node, String alignment) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        !const {'left', 'center', 'right'}.contains(alignment)) {
      return false;
    }
    final block = _textAlignmentBlock(node);
    if (block == null || xmlTextAlignment(node) == alignment) return false;
    _undoManager?.stopCapturing();
    if (alignment == 'left') {
      block.removeAttribute('textAlign');
    } else {
      block.setAttribute('textAlign', alignment);
    }
    notifyListeners();
    return true;
  }

  /// 将顶层段落、标题或代码块转换为另一种文本块，保留正文和 marks。
  yjs.YXmlText? transformXmlTextBlock(
      yjs.YXmlText node, RichDocumentBlockType type) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        !const {
          RichDocumentBlockType.paragraph,
          RichDocumentBlockType.heading1,
          RichDocumentBlockType.heading2,
          RichDocumentBlockType.heading3,
          RichDocumentBlockType.codeBlock,
        }.contains(type) ||
        xmlTextBlockType(node) == null) {
      return null;
    }
    final block = _topLevelBlock(node)!;
    final index = _body.toArray().indexOf(block);
    if (index < 0) return null;
    _undoManager?.stopCapturing();
    final replacement = _createTextBlock(type, node.toString(),
        type == RichDocumentBlockType.codeBlock ? const {} : _marksFor(node));
    final alignment = xmlTextAlignment(node);
    if (type != RichDocumentBlockType.codeBlock && alignment != 'left') {
      replacement.block.setAttribute('textAlign', alignment);
    }
    _document.transact((_) {
      _body.delete(index);
      _body.insert(index, [replacement.block]);
    });
    notifyListeners();
    return replacement.text;
  }

  /// 在当前顶层块之前或之后插入可直接编辑的空段落。
  yjs.YXmlText? insertParagraphNear(yjs.YXmlText node, {required bool after}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return null;
    }
    final block = _topLevelBlock(node);
    if (block == null) return null;
    final index = _body.toArray().indexOf(block);
    if (index < 0) return null;
    _undoManager?.stopCapturing();
    final paragraph = _createTextBlock(RichDocumentBlockType.paragraph, '');
    _document.transact((_) {
      _body.insert(index + (after ? 1 : 0), [paragraph.block]);
    });
    notifyListeners();
    return paragraph.text;
  }

  /// 删除当前顶层块；删除最后一块时保留一个空段落供继续编辑。
  yjs.YXmlText? deleteXmlTextBlock(yjs.YXmlText node) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return null;
    }
    final block = _topLevelBlock(node);
    if (block == null) return null;
    final index = _body.toArray().indexOf(block);
    if (index < 0) return null;
    _undoManager?.stopCapturing();
    yjs.YXmlText? replacement;
    _document.transact((_) {
      _body.delete(index);
      if (_body.length == 0) {
        final paragraph = _createTextBlock(RichDocumentBlockType.paragraph, '');
        _body.insert(0, [paragraph.block]);
        replacement = paragraph.text;
      }
    });
    notifyListeners();
    return replacement;
  }

  /// 在当前块之后插入标准 Tiptap 表格，并返回首个表头单元格文本。
  yjs.YXmlText? insertTable(
      {yjs.YXmlText? near, required int rows, required int columns}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        rows < 1 ||
        rows > 10 ||
        columns < 1 ||
        columns > 10) {
      return null;
    }
    var index = _body.length;
    if (near != null) {
      final block = _topLevelBlock(near);
      final blockIndex = block == null ? -1 : _body.toArray().indexOf(block);
      if (blockIndex >= 0) index = blockIndex + 1;
    }
    final table = yjs.YXmlElement('table');
    yjs.YXmlText? firstText;
    final tableRows = <yjs.YXmlElement>[];
    for (var rowIndex = 0; rowIndex < rows; rowIndex++) {
      final row = yjs.YXmlElement('tableRow');
      final cells = <yjs.YXmlElement>[];
      for (var columnIndex = 0; columnIndex < columns; columnIndex++) {
        final cell =
            yjs.YXmlElement(rowIndex == 0 ? 'tableHeader' : 'tableCell');
        final paragraph = yjs.YXmlElement('paragraph');
        final text = yjs.YXmlText();
        firstText ??= text;
        paragraph.insert(0, [text]);
        cell.insert(0, [paragraph]);
        cells.add(cell);
      }
      row.insert(0, cells);
      tableRows.add(row);
    }
    table.insert(0, tableRows);
    _undoManager?.stopCapturing();
    _document.transact((_) => _body.insert(index, [table]));
    notifyListeners();
    return firstText;
  }

  /// 在当前块之后插入标准 documentImage 占位节点。
  yjs.YXmlElement? insertDocumentImage({yjs.YXmlText? near}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return null;
    }
    var index = _body.length;
    if (near != null) {
      final block = _topLevelBlock(near);
      final blockIndex = block == null ? -1 : _body.toArray().indexOf(block);
      if (blockIndex >= 0) index = blockIndex + 1;
    }
    final image = yjs.YXmlElement('documentImage')
      ..setAttribute('alignment', 'center')
      ..setAttribute('alt', '')
      ..setAttribute('width', 100);
    _undoManager?.stopCapturing();
    _document.transact((_) => _body.insert(index, [image]));
    notifyListeners();
    return image;
  }

  RichDocumentImageAttributes documentImageAttributes(yjs.YXmlElement image) {
    final alignment = image.getAttribute('alignment');
    final alt = image.getAttribute('alt');
    final externalUrl = image.getAttribute('externalUrl');
    final fileId = image.getAttribute('fileId');
    final width = image.getAttribute('width');
    return (
      alignment: alignment == 'left' || alignment == 'right'
          ? alignment as String
          : 'center',
      alt: alt is String ? String.fromCharCodes(alt.runes.take(500)) : '',
      externalUrl: externalUrl is String && externalUrl.trim().isNotEmpty
          ? externalUrl.trim()
          : null,
      fileId:
          fileId is String && fileId.trim().isNotEmpty ? fileId.trim() : null,
      width: width is num && width >= 20 && width <= 100
          ? ((width / 5).round() * 5).clamp(20, 100)
          : 100,
    );
  }

  bool updateDocumentImage(
      yjs.YXmlElement image, RichDocumentImageAttributes attributes) {
    final external = attributes.externalUrl?.trim();
    final externalUri = external == null ? null : Uri.tryParse(external);
    final fileId = attributes.fileId?.trim();
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        image.name != 'documentImage' ||
        !_body.toArray().contains(image) ||
        !const {'left', 'center', 'right'}.contains(attributes.alignment) ||
        (external != null &&
            (externalUri == null ||
                externalUri.scheme != 'https' ||
                externalUri.host.isEmpty)) ||
        (fileId != null && !RegExp(r'^[\w-]{1,200}$').hasMatch(fileId))) {
      return false;
    }
    final width = ((attributes.width / 5).round() * 5).clamp(20, 100);
    _undoManager?.stopCapturing();
    _document.transact((_) {
      image
        ..setAttribute('alignment', attributes.alignment)
        ..setAttribute(
            'alt', String.fromCharCodes(attributes.alt.runes.take(500)))
        ..setAttribute('width', width);
      if (external == null) {
        image.removeAttribute('externalUrl');
      } else {
        image.setAttribute('externalUrl', external);
      }
      if (fileId == null) {
        image.removeAttribute('fileId');
      } else {
        image.setAttribute('fileId', fileId);
      }
    });
    notifyListeners();
    return true;
  }

  bool deleteDocumentImage(yjs.YXmlElement image) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        image.name != 'documentImage') {
      return false;
    }
    final index = _body.toArray().indexOf(image);
    if (index < 0) return false;
    _undoManager?.stopCapturing();
    _document.transact((_) => _body.delete(index));
    notifyListeners();
    return true;
  }

  /// 在富文档末尾追加一个标准 Tiptap XML block。
  ///
  /// 返回 `false` 表示当前不是已同步的富文档或正文为空；此时调用方可
  /// 保留输入内容而不产生任何 Yjs 更新。
  bool appendTextBlock(String value,
      {RichDocumentBlockType type = RichDocumentBlockType.paragraph}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        value.trim().isEmpty) {
      return false;
    }
    final text = value.trim();
    _undoManager?.stopCapturing();
    _document.transact((_) {
      if (type == RichDocumentBlockType.bulletList ||
          type == RichDocumentBlockType.orderedList ||
          type == RichDocumentBlockType.taskList) {
        final list = yjs.YXmlElement(_blockName(type));
        final item = yjs.YXmlElement(
            type == RichDocumentBlockType.taskList ? 'taskItem' : 'listItem');
        if (type == RichDocumentBlockType.taskList) {
          item.setAttribute('checked', false);
        }
        final paragraph = yjs.YXmlElement('paragraph');
        paragraph.insert(0, [yjs.YXmlText()..insert(0, text)]);
        item.insert(0, [paragraph]);
        list.insert(0, [item]);
        _body.insert(_body.length, [list]);
      } else if (type == RichDocumentBlockType.blockquote) {
        // Tiptap 的 blockquote 内容是 block+，不能直接挂 Y.XmlText；
        // 使用 paragraph 子节点保持与 Web/Desktop schema 一致。
        final block = yjs.YXmlElement('blockquote');
        final paragraph = yjs.YXmlElement('paragraph');
        paragraph.insert(0, [yjs.YXmlText()..insert(0, text)]);
        block.insert(0, [paragraph]);
        _body.insert(_body.length, [block]);
      } else {
        final block = yjs.YXmlElement(_blockName(type));
        if (type == RichDocumentBlockType.heading1 ||
            type == RichDocumentBlockType.heading2 ||
            type == RichDocumentBlockType.heading3) {
          block.setAttribute(
              'level',
              type == RichDocumentBlockType.heading1
                  ? 1
                  : type == RichDocumentBlockType.heading2
                      ? 2
                      : 3);
        }
        block.insert(0, [yjs.YXmlText()..insert(0, text)]);
        _body.insert(_body.length, [block]);
      }
    });
    notifyListeners();
    return true;
  }

  String _blockName(RichDocumentBlockType type) => switch (type) {
        RichDocumentBlockType.paragraph => 'paragraph',
        RichDocumentBlockType.heading1 ||
        RichDocumentBlockType.heading2 ||
        RichDocumentBlockType.heading3 =>
          'heading',
        RichDocumentBlockType.bulletList => 'bulletList',
        RichDocumentBlockType.orderedList => 'orderedList',
        RichDocumentBlockType.taskList => 'taskList',
        RichDocumentBlockType.blockquote => 'blockquote',
        RichDocumentBlockType.codeBlock => 'codeBlock',
      };

  ({yjs.YXmlElement block, yjs.YXmlText text}) _createTextBlock(
      RichDocumentBlockType type, String value,
      [Map<String, Object?> marks = const {}]) {
    final block = yjs.YXmlElement(_blockName(type));
    if (type == RichDocumentBlockType.heading1 ||
        type == RichDocumentBlockType.heading2 ||
        type == RichDocumentBlockType.heading3) {
      block.setAttribute(
          'level',
          type == RichDocumentBlockType.heading1
              ? 1
              : type == RichDocumentBlockType.heading2
                  ? 2
                  : 3);
    }
    final text = yjs.YXmlText();
    block.insert(0, [text]);
    if (value.isNotEmpty) text.insert(0, value, marks);
    return (block: block, text: text);
  }

  yjs.YXmlElement? _topLevelBlock(yjs.YXmlText node) {
    yjs.AbstractType<dynamic>? current = node.parent;
    while (current is yjs.YXmlElement) {
      if (identical(current.parent, _body)) return current;
      current = current.parent;
    }
    return null;
  }

  yjs.YXmlElement? _textAlignmentBlock(yjs.YXmlText node) {
    yjs.AbstractType<dynamic>? current = node.parent;
    while (current is yjs.YXmlElement) {
      if (current.name == 'paragraph' || current.name == 'heading') {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  /// 将轻量编辑器中的纯文本转换为标准 Tiptap XML block tree。
  ///
  /// 每行对应一个 `paragraph`，后续富文本工具栏可直接在 [body] 上插入
  /// heading、list 等 `YXmlElement`，无需改变协作协议或持久化字段。
  void _replaceBodyText(String value) {
    final lines = value.split('\n');
    final textNodes = <yjs.YXmlText>[];
    _collectXmlTextNodes(_body, textNodes);
    // Update existing text leaves in place so images, tables, lists and
    // formatting attributes from a Web/Desktop document are not discarded by
    // a plain-text edit in Flutter.
    for (var i = 0; i < textNodes.length; i++) {
      final node = textNodes[i];
      final next = i < lines.length ? lines[i] : '';
      if (node.toString() == next) continue;
      final marks = _marksFor(node);
      _clearText(node);
      if (next.isNotEmpty) node.insert(0, next, marks);
      if (i >= lines.length && node.parent is yjs.YXmlElement) {
        final paragraph = node.parent!;
        if (paragraph.name == 'paragraph' && paragraph.length == 1) {
          final owner = paragraph.parent;
          if (owner is yjs.YXmlFragment) {
            final index = owner.toArray().indexOf(paragraph);
            if (index >= 0) owner.delete(index);
          }
        }
      }
    }
    if (lines.length <= textNodes.length) return;
    for (final line in lines.skip(textNodes.length)) {
      final paragraph = yjs.YXmlElement('paragraph');
      _body.insert(_body.length, [paragraph]);
      final content = yjs.YXmlText();
      paragraph.insert(0, [content]);
      if (line.isNotEmpty) content.insert(0, line);
    }
  }

  void _collectXmlTextNodes(yjs.YXmlFragment node, List<yjs.YXmlText> result) {
    for (final child in node.toArray()) {
      if (child is yjs.YXmlText) {
        result.add(child);
      } else if (child is yjs.YXmlFragment) {
        _collectXmlTextNodes(child, result);
      }
    }
  }

  Map<String, Object?> _marksFor(yjs.YXmlText node) {
    final delta = node.toDelta();
    if (delta.isEmpty) return const {};
    final attributes = delta.first['attributes'];
    return attributes is Map ? Map<String, Object?>.from(attributes) : const {};
  }

  void _clearText(yjs.YXmlText node) {
    if (node.length > 0) node.delete(0, node.length);
  }

  void _replaceTextRange(yjs.YText text, String current, String next,
      {Map<String, Object?> attributes = const {}}) {
    final change = _textChange(current, next);
    if (change.deleteLength > 0) {
      if (current.isNotEmpty) text.delete(0, current.length);
      if (next.isNotEmpty) text.insert(0, next, attributes);
      return;
    }
    if (change.insertion.isNotEmpty) {
      text.insert(change.prefix, change.insertion, attributes);
    }
  }

  bool _isBulkTextChange(String current, String next) {
    final change = _textChange(current, next);
    return change.deleteLength > 0 || change.insertion.runes.length > 1;
  }

  ({int prefix, int deleteLength, String insertion}) _textChange(
      String current, String next) {
    final currentRunes = current.runes.toList(growable: false);
    final nextRunes = next.runes.toList(growable: false);
    var prefixRunes = 0;
    while (prefixRunes < currentRunes.length &&
        prefixRunes < nextRunes.length &&
        currentRunes[prefixRunes] == nextRunes[prefixRunes]) {
      prefixRunes++;
    }
    var suffixRunes = 0;
    while (suffixRunes < currentRunes.length - prefixRunes &&
        suffixRunes < nextRunes.length - prefixRunes &&
        currentRunes[currentRunes.length - suffixRunes - 1] ==
            nextRunes[nextRunes.length - suffixRunes - 1]) {
      suffixRunes++;
    }
    final prefix = String.fromCharCodes(currentRunes.take(prefixRunes)).length;
    final currentSuffix = String.fromCharCodes(
            currentRunes.skip(currentRunes.length - suffixRunes))
        .length;
    final nextSuffix =
        String.fromCharCodes(nextRunes.skip(nextRunes.length - suffixRunes))
            .length;
    final deleteLength = current.length - prefix - currentSuffix;
    final insertion = next.substring(prefix, next.length - nextSuffix);
    return (
      prefix: prefix,
      deleteLength: deleteLength,
      insertion: insertion,
    );
  }

  String _readBodyText() {
    final blocks = _body.toArray().map(_xmlNodeText).toList();
    return blocks.join('\n');
  }

  String _xmlNodeText(Object? value) {
    if (value is yjs.YXmlText || value is yjs.YText) return value.toString();
    if (value is! yjs.YXmlFragment) return value is String ? value : '';
    final children = value.toArray().map(_xmlNodeText).toList();
    final name = value.name;
    if (name == 'bulletList' ||
        name == 'orderedList' ||
        name == 'taskList' ||
        name == 'listItem' ||
        name == 'taskItem' ||
        name == 'tableRow') {
      return children.join('\n');
    }
    if (name == 'tableCell' || name == 'tableHeader') {
      return children.join(' ');
    }
    return children.join();
  }

  void _onDocumentUpdate(dynamic update,
      [dynamic origin, dynamic _, dynamic __]) {
    if (_closed || identical(origin, this) || update is! Uint8List) return;
    final encoder = yjs.createEncoder();
    yjs.writeVarString(encoder, documentId);
    yjs.writeVarUint(encoder, yjsMessageSync);
    yjs.writeUpdate(encoder, update);
    unawaited(_sendFrame(yjs.toUint8Array(encoder)));
  }

  void _onAwarenessUpdate(dynamic changes, [dynamic origin]) {
    if (_closed || !_authenticated || origin != 'local' || changes is! Map) {
      return;
    }
    final clients = <int>[];
    for (final key in const ['added', 'updated', 'removed']) {
      final values = changes[key];
      if (values is List) clients.addAll(values.whereType<int>());
    }
    if (clients.isEmpty) return;
    unawaited(_sendAwareness(clients.toSet().toList()));
    notifyListeners();
  }

  Future<void> _sendAwareness(List<int> clients) async {
    final update = yjs.encodeAwarenessUpdate(_awareness, clients);
    final encoder = yjs.createEncoder();
    yjs.writeVarString(encoder, documentId);
    yjs.writeVarUint(encoder, HocuspocusMessageType.awareness);
    yjs.writeVarUint8Array(encoder, update);
    await _sendFrame(yjs.toUint8Array(encoder));
  }

  void _onFrame(Uint8List frame) {
    if (_closed) return;
    final decoder = yjs.createDecoder(frame);
    final name = yjs.readVarString(decoder);
    if (name != documentId || !yjs.hasContent(decoder)) return;
    final type = yjs.readVarUint(decoder);
    if (type == HocuspocusMessageType.auth) {
      if (yjs.hasContent(decoder) && yjs.readVarUint(decoder) == 2) {
        _authenticated = true;
        unawaited(_sendAwareness([_awareness.clientID]));
      }
      return;
    }
    if (type == HocuspocusMessageType.awareness) {
      final update = yjs.readVarUint8Array(decoder);
      yjs.applyAwarenessUpdate(_awareness, update, this);
      notifyListeners();
      return;
    }
    if (type == HocuspocusMessageType.queryAwareness) {
      unawaited(_sendAwareness(_awareness.states.keys.toList()));
      return;
    }
    if (type != yjsMessageSync) return;
    final encoder = yjs.createEncoder();
    yjs.writeVarString(encoder, documentId);
    yjs.writeVarUint(encoder, yjsMessageSync);
    final prefixLength = encoder.length;
    final previousText = text;
    final messageType = yjs.readSyncMessage(decoder, encoder, _document, this);
    if (encoder.length > prefixLength) {
      unawaited(_sendFrame(yjs.toUint8Array(encoder)));
    }
    final becameSynced = messageType == yjs.messageSyncStep2 &&
        status != DocumentCollaborationStatus.synced;
    if (becameSynced) {
      status = DocumentCollaborationStatus.synced;
      notifyListeners();
    } else if (text != previousText) {
      // A later Yjs update is a remote edit after the initial handshake.
      notifyListeners();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _authenticated = false;
    _document.off('update', _onDocumentUpdate);
    _awareness.off('update', _onAwarenessUpdate);
    _handlersAttached = false;
    _awareness.destroy();
    await _subscription?.cancel();
    await _realtime.close();
    status = DocumentCollaborationStatus.disconnected;
    notifyListeners();
  }

  Future<void> _sendFrame(Uint8List frame) async {
    try {
      await _realtime.send(frame);
    } catch (_) {
      _markError();
    }
  }

  void _markError() {
    if (_closed || status == DocumentCollaborationStatus.error) return;
    status = DocumentCollaborationStatus.error;
    notifyListeners();
  }
}

const yjsMessageSync = yjs.messageSyncStep1;
