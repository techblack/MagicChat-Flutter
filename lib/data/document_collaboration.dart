import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import '../domain/rich_document_format.dart';
import 'document_realtime.dart';

enum DocumentCollaborationStatus { disconnected, connecting, synced, error }

/// Flutter 富文档开放的官方 block 类型。
///
/// 新块按 Tiptap schema 插入；结构转换只处理已识别的安全树，并保留文本
/// marks。包含未知子节点的结构不会被重写。
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

enum RichDocumentTableAction {
  addRowBefore,
  addRowAfter,
  deleteRow,
  addColumnBefore,
  addColumnAfter,
  deleteColumn,
  deleteTable,
}

typedef RichDocumentTableEditResult = ({
  bool changed,
  yjs.YXmlText? selection,
});

typedef RichDocumentImageAttributes = ({
  String alignment,
  String alt,
  String? externalUrl,
  String? fileId,
  int width,
});

typedef RichDocumentHorizontalRuleAttributes = ({
  String lineStyle,
  int thickness,
});

RichDocumentHorizontalRuleAttributes normalizeRichDocumentHorizontalRule(
    Object? lineStyle, Object? thickness) {
  final style = const {'dashed', 'dotted', 'double'}.contains(lineStyle)
      ? lineStyle as String
      : 'solid';
  final parsed = thickness is num ? thickness : num.tryParse('$thickness');
  final width =
      (parsed?.isFinite == true ? parsed!.round() : 1).clamp(1, 6).toInt();
  return (lineStyle: style, thickness: width);
}

class _RichTextSnapshot {
  const _RichTextSnapshot({
    required this.source,
    required this.delta,
    required this.alignment,
    required this.group,
    required this.checked,
  });

  final yjs.YXmlText source;
  final List<Map<String, Object?>> delta;
  final String alignment;
  final int group;
  final bool checked;
}

class _PendingRichText {
  const _PendingRichText(
    this.source,
    this.target,
    this.delta, {
    required this.keepMarks,
  });

  final yjs.YXmlText source;
  final yjs.YXmlText target;
  final List<Map<String, Object?>> delta;
  final bool keepMarks;
}

class _RichStructureReplacement {
  const _RichStructureReplacement(this.blocks, this.pending);

  final List<yjs.YXmlElement> blocks;
  final List<_PendingRichText> pending;
}

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
    _subscription = _realtime.events.listen(
      _onFrame,
      onError: (_) {
        _markError();
      },
      onDone: _markError,
    );
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
  void replaceXmlText(
    yjs.YXmlText node,
    String value, {
    Map<String, Object?>? marks,
  }) {
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

  /// 返回当前文本所在的可安全转换结构类型。
  ///
  /// 顶层列表和引用按整体转换；表格单元格只转换单元格内的当前块。包含
  /// 未知或嵌套节点的结构不开放转换，避免覆盖其他客户端写入的内容。
  RichDocumentBlockType? xmlTextBlockType(yjs.YXmlText node) {
    final block = _editableStructureBlock(node);
    final type = block == null ? null : _richBlockType(block);
    final snapshots = block == null ? null : _structureSnapshots(block);
    return type != null &&
            snapshots != null &&
            snapshots.any((snapshot) => identical(snapshot.source, node))
        ? type
        : null;
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

  /// 返回文本所在顶层块的官方背景色；未知色值不进入 Flutter 展示与编辑。
  String? xmlTextBlockBackground(yjs.YXmlText node) {
    final block = _topLevelBlock(node);
    if (block == null || !_supportsBlockBackground(block)) return null;
    return normalizeRichDocumentBlockBackground(
      block.getAttribute('blockBackgroundColor'),
    );
  }

  /// 设置或清除文本所在顶层块的背景，写入 Web/Desktop 共用的 Yjs 属性。
  bool setXmlTextBlockBackground(yjs.YXmlText node, String? color) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        (color != null &&
            normalizeRichDocumentBlockBackground(color) != color)) {
      return false;
    }
    final block = _topLevelBlock(node);
    if (block == null || !_supportsBlockBackground(block)) return false;
    final current = block.getAttribute('blockBackgroundColor');
    if (current == color) return false;
    _undoManager?.stopCapturing();
    if (color == null) {
      block.removeAttribute('blockBackgroundColor');
    } else {
      block.setAttribute('blockBackgroundColor', color);
    }
    notifyListeners();
    return true;
  }

  /// 将当前已知结构转换为另一种官方 block，保留全部文本、marks 和列表项。
  yjs.YXmlText? transformXmlTextBlock(
    yjs.YXmlText node,
    RichDocumentBlockType type,
  ) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        xmlTextBlockType(node) == null) {
      return null;
    }
    final block = _editableStructureBlock(node)!;
    if (_richBlockType(block) == type) return node;
    final snapshots = _structureSnapshots(block);
    final parent = block.parent;
    if (snapshots == null || parent is! yjs.YXmlFragment) return null;
    final index = parent.toArray().indexOf(block);
    if (index < 0) return null;
    final background = normalizeRichDocumentBlockBackground(
      block.getAttribute('blockBackgroundColor'),
    );
    final replacement = _createStructureReplacement(
      snapshots,
      type,
      blockBackground: background,
    );
    if (replacement == null) return null;
    _undoManager?.stopCapturing();
    yjs.YXmlText? selected;
    _document.transact((_) {
      parent.delete(index);
      parent.insert(index, replacement.blocks);
      for (final pending in replacement.pending) {
        _applyTextDelta(
          pending.target,
          pending.delta,
          keepMarks: pending.keepMarks,
        );
        if (identical(pending.source, node)) selected = pending.target;
      }
    });
    _undoManager?.stopCapturing();
    notifyListeners();
    return selected;
  }

  /// 在当前结构块之前或之后插入可直接编辑的空段落。
  yjs.YXmlText? insertParagraphNear(yjs.YXmlText node, {required bool after}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return null;
    }
    final block = _editableStructureBlock(node);
    if (block == null) return null;
    final parent = block.parent;
    if (parent is! yjs.YXmlFragment) return null;
    final index = parent.toArray().indexOf(block);
    if (index < 0) return null;
    _undoManager?.stopCapturing();
    final paragraph = _createTextBlock(RichDocumentBlockType.paragraph, '');
    _document.transact((_) {
      parent.insert(index + (after ? 1 : 0), [paragraph.block]);
    });
    notifyListeners();
    return paragraph.text;
  }

  /// 删除当前结构块；删除父节点最后一块时保留空段落供继续编辑。
  yjs.YXmlText? deleteXmlTextBlock(yjs.YXmlText node) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return null;
    }
    final block = _editableStructureBlock(node);
    if (block == null) return null;
    final parent = block.parent;
    if (parent is! yjs.YXmlFragment) return null;
    final index = parent.toArray().indexOf(block);
    if (index < 0) return null;
    _undoManager?.stopCapturing();
    yjs.YXmlText? replacement;
    _document.transact((_) {
      parent.delete(index);
      if (parent.length == 0) {
        final paragraph = _createTextBlock(RichDocumentBlockType.paragraph, '');
        parent.insert(0, [paragraph.block]);
        replacement = paragraph.text;
      }
    });
    notifyListeners();
    return replacement;
  }

  /// 在当前结构块之后插入官方 horizontalRule，默认使用 1px 实线。
  yjs.YXmlElement? insertHorizontalRule({yjs.YXmlText? near}) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return null;
    }
    yjs.YXmlFragment parent = _body;
    var index = parent.length;
    if (near != null) {
      final block = _editableStructureBlock(near);
      final blockParent = block?.parent;
      if (block != null && blockParent is yjs.YXmlFragment) {
        final blockIndex = blockParent.toArray().indexOf(block);
        if (blockIndex >= 0) {
          parent = blockParent;
          index = blockIndex + 1;
        }
      }
    }
    final rule = yjs.YXmlElement('horizontalRule')
      ..setAttribute('lineStyle', 'solid')
      ..setAttribute('thickness', 1);
    _undoManager?.stopCapturing();
    _document.transact((_) => parent.insert(index, [rule]));
    _undoManager?.stopCapturing();
    notifyListeners();
    return rule;
  }

  RichDocumentHorizontalRuleAttributes horizontalRuleAttributes(
    yjs.YXmlElement rule,
  ) =>
      normalizeRichDocumentHorizontalRule(
        rule.getAttribute('lineStyle'),
        rule.getAttribute('thickness'),
      );

  bool updateHorizontalRule(
    yjs.YXmlElement rule,
    RichDocumentHorizontalRuleAttributes attributes,
  ) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        rule.name != 'horizontalRule' ||
        !_isDescendantOfBody(rule) ||
        !const {
          'solid',
          'dashed',
          'dotted',
          'double',
        }.contains(attributes.lineStyle) ||
        attributes.thickness < 1 ||
        attributes.thickness > 6) {
      return false;
    }
    final current = horizontalRuleAttributes(rule);
    if (current == attributes) return false;
    _undoManager?.stopCapturing();
    _document.transact((_) {
      rule
        ..setAttribute('lineStyle', attributes.lineStyle)
        ..setAttribute('thickness', attributes.thickness);
    });
    _undoManager?.stopCapturing();
    notifyListeners();
    return true;
  }

  bool deleteHorizontalRule(yjs.YXmlElement rule) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        rule.name != 'horizontalRule' ||
        !_isDescendantOfBody(rule)) {
      return false;
    }
    final parent = rule.parent;
    if (parent is! yjs.YXmlFragment) return false;
    final index = parent.toArray().indexOf(rule);
    if (index < 0) return false;
    _undoManager?.stopCapturing();
    _document.transact((_) {
      parent.delete(index);
      if (parent.length == 0) {
        final paragraph = _createTextBlock(RichDocumentBlockType.paragraph, '');
        parent.insert(0, [paragraph.block]);
      }
    });
    _undoManager?.stopCapturing();
    notifyListeners();
    return true;
  }

  bool setTaskItemChecked(yjs.YXmlElement item, bool checked) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced ||
        item.name != 'taskItem' ||
        !_isDescendantOfBody(item) ||
        item.getAttribute('checked') == checked) {
      return false;
    }
    _undoManager?.stopCapturing();
    item.setAttribute('checked', checked);
    _undoManager?.stopCapturing();
    notifyListeners();
    return true;
  }

  /// 在当前块之后插入标准 Tiptap 表格，并返回首个表头单元格文本。
  yjs.YXmlText? insertTable({
    yjs.YXmlText? near,
    required int rows,
    required int columns,
  }) {
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
        final cell = yjs.YXmlElement(
          rowIndex == 0 ? 'tableHeader' : 'tableCell',
        );
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

  bool isXmlTextInEditableTable(yjs.YXmlText node) =>
      _editableTableSelection(node) != null;

  /// 编辑当前单元格所在的标准 Tiptap 表格，并返回操作后的可编辑位置。
  ///
  /// 只接受 body 直属、行列等宽且没有合并单元格的表格。已有单元格的
  /// attributes 和未知嵌套内容不会被重建。
  RichDocumentTableEditResult editTable(
      yjs.YXmlText node, RichDocumentTableAction action) {
    if (documentType != 'document' ||
        status != DocumentCollaborationStatus.synced) {
      return (changed: false, selection: null);
    }
    final selected = _editableTableSelection(node);
    if (selected == null) return (changed: false, selection: null);
    _undoManager?.stopCapturing();
    yjs.YXmlText? next;
    switch (action) {
      case RichDocumentTableAction.addRowBefore:
      case RichDocumentTableAction.addRowAfter:
        final insertAt = selected.rowIndex +
            (action == RichDocumentTableAction.addRowAfter ? 1 : 0);
        final created = _createTableRow(
            selected.cells.map((cell) => cell.name!).toList(growable: false));
        _document
            .transact((_) => selected.table.insert(insertAt, [created.row]));
        next = created.texts[selected.columnIndex];
        break;
      case RichDocumentTableAction.deleteRow:
        if (selected.rows.length == 1) {
          next = _deleteTable(selected.table);
        } else {
          _document.transact((_) => selected.table.delete(selected.rowIndex));
          final rows = _tableRows(selected.table);
          final nextRow =
              rows[selected.rowIndex.clamp(0, rows.length - 1).toInt()];
          next = _firstXmlText(_tableCells(nextRow)[selected.columnIndex]);
        }
        break;
      case RichDocumentTableAction.addColumnBefore:
      case RichDocumentTableAction.addColumnAfter:
        final insertAt = selected.columnIndex +
            (action == RichDocumentTableAction.addColumnAfter ? 1 : 0);
        _document.transact((_) {
          for (final row in selected.rows) {
            final reference = _tableCells(row)[selected.columnIndex];
            final created = _createTableCell(reference.name!);
            row.insert(insertAt, [created.cell]);
            if (identical(row, selected.row)) next = created.text;
          }
        });
        break;
      case RichDocumentTableAction.deleteColumn:
        if (selected.cells.length == 1) {
          next = _deleteTable(selected.table);
        } else {
          _document.transact((_) {
            for (final row in selected.rows) {
              row.delete(selected.columnIndex);
            }
          });
          final cells = _tableCells(selected.row);
          next = _firstXmlText(
              cells[selected.columnIndex.clamp(0, cells.length - 1).toInt()]);
        }
        break;
      case RichDocumentTableAction.deleteTable:
        next = _deleteTable(selected.table);
        break;
    }
    _undoManager?.stopCapturing();
    notifyListeners();
    return (changed: true, selection: next);
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
    yjs.YXmlElement image,
    RichDocumentImageAttributes attributes,
  ) {
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
          'alt',
          String.fromCharCodes(attributes.alt.runes.take(500)),
        )
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
  bool appendTextBlock(
    String value, {
    RichDocumentBlockType type = RichDocumentBlockType.paragraph,
  }) {
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
          type == RichDocumentBlockType.taskList ? 'taskItem' : 'listItem',
        );
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
                    : 3,
          );
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
    RichDocumentBlockType type,
    String value, [
    Map<String, Object?> marks = const {},
  ]) {
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
                : 3,
      );
    }
    final text = yjs.YXmlText();
    block.insert(0, [text]);
    if (value.isNotEmpty) text.insert(0, value, marks);
    return (block: block, text: text);
  }

  RichDocumentBlockType? _richBlockType(yjs.YXmlElement block) =>
      switch (block.name) {
        'paragraph' => RichDocumentBlockType.paragraph,
        'heading' => switch ((block.getAttribute('level') as num?)?.toInt()) {
            1 => RichDocumentBlockType.heading1,
            3 => RichDocumentBlockType.heading3,
            _ => RichDocumentBlockType.heading2,
          },
        'bulletList' => RichDocumentBlockType.bulletList,
        'orderedList' => RichDocumentBlockType.orderedList,
        'taskList' => RichDocumentBlockType.taskList,
        'blockquote' => RichDocumentBlockType.blockquote,
        'codeBlock' => RichDocumentBlockType.codeBlock,
        _ => null,
      };

  yjs.YXmlElement? _editableStructureBlock(yjs.YXmlText node) {
    yjs.YXmlElement? candidate;
    yjs.AbstractType<dynamic>? current = node.parent;
    while (current is yjs.YXmlElement) {
      if (current.name == 'tableCell' || current.name == 'tableHeader') {
        return candidate;
      }
      candidate = current;
      if (identical(current.parent, _body)) return current;
      current = current.parent;
    }
    return null;
  }

  List<_RichTextSnapshot>? _structureSnapshots(yjs.YXmlElement block) {
    final type = _richBlockType(block);
    if (type == null) return null;
    if (type == RichDocumentBlockType.bulletList ||
        type == RichDocumentBlockType.orderedList ||
        type == RichDocumentBlockType.taskList) {
      final items = block.toArray();
      if (items.isEmpty || items.any((item) => item is! yjs.YXmlElement)) {
        return null;
      }
      final result = <_RichTextSnapshot>[];
      for (var index = 0; index < items.length; index++) {
        final item = items[index]! as yjs.YXmlElement;
        final expected =
            type == RichDocumentBlockType.taskList ? 'taskItem' : 'listItem';
        if (item.name != expected) {
          return null;
        }
        final children = item.toArray();
        if (children.isEmpty ||
            children.any(
              (child) => child is! yjs.YXmlElement || child.name != 'paragraph',
            )) {
          return null;
        }
        for (final child in children.whereType<yjs.YXmlElement>()) {
          final snapshot = _textBlockSnapshot(
            child,
            group: index,
            checked: item.getAttribute('checked') == true,
          );
          if (snapshot == null) return null;
          result.add(snapshot);
        }
      }
      return result;
    }
    if (type == RichDocumentBlockType.blockquote) {
      final children = block.toArray();
      if (children.isEmpty ||
          children.any(
            (child) =>
                child is! yjs.YXmlElement ||
                !const {
                  'paragraph',
                  'heading',
                  'codeBlock',
                }.contains(child.name),
          )) {
        return null;
      }
      final result = <_RichTextSnapshot>[];
      for (var index = 0; index < children.length; index++) {
        final snapshot = _textBlockSnapshot(
          children[index]! as yjs.YXmlElement,
          group: index,
        );
        if (snapshot == null) return null;
        result.add(snapshot);
      }
      return result;
    }
    final snapshot = _textBlockSnapshot(block, group: 0);
    return snapshot == null ? null : [snapshot];
  }

  _RichTextSnapshot? _textBlockSnapshot(
    yjs.YXmlElement block, {
    required int group,
    bool checked = false,
  }) {
    final children = block.toArray();
    if (children.length != 1 || children.single is! yjs.YXmlText) return null;
    final text = children.single! as yjs.YXmlText;
    final delta = <Map<String, Object?>>[];
    for (final operation in text.toDelta()) {
      if (operation['insert'] is! String) return null;
      final copy = <String, Object?>{'insert': operation['insert']};
      final attributes = operation['attributes'];
      if (attributes is Map) {
        copy['attributes'] = Map<String, Object?>.from(attributes);
      }
      delta.add(copy);
    }
    final alignment = block.getAttribute('textAlign');
    return _RichTextSnapshot(
      source: text,
      delta: delta,
      alignment: alignment == 'center' || alignment == 'right'
          ? alignment as String
          : 'left',
      group: group,
      checked: checked,
    );
  }

  _RichStructureReplacement? _createStructureReplacement(
    List<_RichTextSnapshot> snapshots,
    RichDocumentBlockType type, {
    String? blockBackground,
  }) {
    if (snapshots.isEmpty) return null;
    final blocks = <yjs.YXmlElement>[];
    final pending = <_PendingRichText>[];
    if (type == RichDocumentBlockType.bulletList ||
        type == RichDocumentBlockType.orderedList ||
        type == RichDocumentBlockType.taskList) {
      final list = yjs.YXmlElement(_blockName(type));
      if (blockBackground != null) {
        list.setAttribute('blockBackgroundColor', blockBackground);
      }
      yjs.YXmlElement? item;
      int? group;
      final items = <yjs.YXmlElement>[];
      final itemBlocks = <yjs.YXmlElement>[];
      void flushItem() {
        final current = item;
        if (current == null) return;
        current.insert(0, List.of(itemBlocks));
        items.add(current);
        itemBlocks.clear();
      }

      for (final snapshot in snapshots) {
        if (group != snapshot.group) {
          flushItem();
          group = snapshot.group;
          item = yjs.YXmlElement(
            type == RichDocumentBlockType.taskList ? 'taskItem' : 'listItem',
          );
          if (type == RichDocumentBlockType.taskList) {
            item.setAttribute('checked', snapshot.checked);
          }
        }
        final created = _createTextBlock(RichDocumentBlockType.paragraph, '');
        if (snapshot.alignment != 'left') {
          created.block.setAttribute('textAlign', snapshot.alignment);
        }
        itemBlocks.add(created.block);
        pending.add(
          _PendingRichText(
            snapshot.source,
            created.text,
            snapshot.delta,
            keepMarks: true,
          ),
        );
      }
      flushItem();
      list.insert(0, items);
      blocks.add(list);
      return _RichStructureReplacement(blocks, pending);
    }
    if (type == RichDocumentBlockType.blockquote) {
      final quote = yjs.YXmlElement('blockquote');
      if (blockBackground != null) {
        quote.setAttribute('blockBackgroundColor', blockBackground);
      }
      final paragraphs = <yjs.YXmlElement>[];
      for (final snapshot in snapshots) {
        final created = _createTextBlock(RichDocumentBlockType.paragraph, '');
        if (snapshot.alignment != 'left') {
          created.block.setAttribute('textAlign', snapshot.alignment);
        }
        paragraphs.add(created.block);
        pending.add(
          _PendingRichText(
            snapshot.source,
            created.text,
            snapshot.delta,
            keepMarks: true,
          ),
        );
      }
      quote.insert(0, paragraphs);
      blocks.add(quote);
      return _RichStructureReplacement(blocks, pending);
    }
    for (final snapshot in snapshots) {
      final created = _createTextBlock(type, '');
      if (type != RichDocumentBlockType.codeBlock &&
          snapshot.alignment != 'left') {
        created.block.setAttribute('textAlign', snapshot.alignment);
      }
      if (blockBackground != null) {
        created.block.setAttribute('blockBackgroundColor', blockBackground);
      }
      blocks.add(created.block);
      pending.add(
        _PendingRichText(
          snapshot.source,
          created.text,
          snapshot.delta,
          keepMarks: type != RichDocumentBlockType.codeBlock,
        ),
      );
    }
    return _RichStructureReplacement(blocks, pending);
  }

  void _applyTextDelta(
    yjs.YXmlText target,
    List<Map<String, Object?>> delta, {
    required bool keepMarks,
  }) {
    for (final operation in delta) {
      final value = operation['insert']! as String;
      final rawAttributes = operation['attributes'];
      final attributes = keepMarks && rawAttributes is Map
          ? Map<String, Object?>.from(rawAttributes)
          : const <String, Object?>{};
      if (value.isNotEmpty) {
        target.insert(target.length, value, attributes);
      }
    }
  }

  bool _isDescendantOfBody(yjs.AbstractType<dynamic> node) {
    yjs.AbstractType<dynamic>? current = node;
    while (current != null) {
      if (identical(current.parent, _body)) return true;
      current = current.parent;
    }
    return false;
  }

  yjs.YXmlElement? _topLevelBlock(yjs.YXmlText node) {
    yjs.AbstractType<dynamic>? current = node.parent;
    while (current is yjs.YXmlElement) {
      if (identical(current.parent, _body)) return current;
      current = current.parent;
    }
    return null;
  }

  _RichTableSelection? _editableTableSelection(yjs.YXmlText node) {
    yjs.AbstractType<dynamic>? current = node.parent;
    yjs.YXmlElement? cell;
    while (current is yjs.YXmlElement) {
      if (current.name == 'tableCell' || current.name == 'tableHeader') {
        cell = current;
        break;
      }
      current = current.parent;
    }
    final row = cell?.parent;
    final table = row?.parent;
    if (cell == null ||
        row is! yjs.YXmlElement ||
        row.name != 'tableRow' ||
        table is! yjs.YXmlElement ||
        table.name != 'table' ||
        !identical(table.parent, _body)) {
      return null;
    }
    final tableChildren = table.toArray();
    final rows = _tableRows(table);
    if (rows.isEmpty || rows.length != tableChildren.length) return null;
    final columnCount = _tableCells(rows.first).length;
    if (columnCount == 0) return null;
    for (final currentRow in rows) {
      final rowChildren = currentRow.toArray();
      final cells = _tableCells(currentRow);
      if (cells.length != columnCount || cells.length != rowChildren.length) {
        return null;
      }
      if (cells.any((currentCell) =>
          !_isSingleSpan(currentCell.getAttribute('colspan')) ||
          !_isSingleSpan(currentCell.getAttribute('rowspan')))) {
        return null;
      }
    }
    final cells = _tableCells(row);
    final rowIndex = rows.indexOf(row);
    final columnIndex = cells.indexOf(cell);
    if (rowIndex < 0 || columnIndex < 0) return null;
    return _RichTableSelection(
        table: table,
        row: row,
        rows: rows,
        cells: cells,
        rowIndex: rowIndex,
        columnIndex: columnIndex);
  }

  bool _isSingleSpan(Object? value) =>
      value == null || value == 1 || value == '1';

  List<yjs.YXmlElement> _tableRows(yjs.YXmlElement table) => table
      .toArray()
      .whereType<yjs.YXmlElement>()
      .where((row) => row.name == 'tableRow')
      .toList(growable: false);

  List<yjs.YXmlElement> _tableCells(yjs.YXmlElement row) => row
      .toArray()
      .whereType<yjs.YXmlElement>()
      .where((cell) => cell.name == 'tableCell' || cell.name == 'tableHeader')
      .toList(growable: false);

  ({yjs.YXmlElement cell, yjs.YXmlText text}) _createTableCell(String name) {
    final cell = yjs.YXmlElement(name == 'tableHeader' ? name : 'tableCell');
    final paragraph = yjs.YXmlElement('paragraph');
    final text = yjs.YXmlText();
    paragraph.insert(0, [text]);
    cell.insert(0, [paragraph]);
    return (cell: cell, text: text);
  }

  ({yjs.YXmlElement row, List<yjs.YXmlText> texts}) _createTableRow(
      List<String> cellTypes) {
    final row = yjs.YXmlElement('tableRow');
    final cells = cellTypes.map(_createTableCell).toList(growable: false);
    row.insert(0, cells.map((value) => value.cell).toList(growable: false));
    return (
      row: row,
      texts: cells.map((value) => value.text).toList(growable: false),
    );
  }

  yjs.YXmlText? _deleteTable(yjs.YXmlElement table) {
    if (!identical(table.parent, _body)) return null;
    final index = _body.toArray().indexOf(table);
    if (index < 0) return null;
    yjs.YXmlText? selection;
    _document.transact((_) {
      _body.delete(index);
      if (_body.length == 0) {
        final paragraph = _createTextBlock(RichDocumentBlockType.paragraph, '');
        _body.insert(0, [paragraph.block]);
        selection = paragraph.text;
      } else {
        final blocks = _body.toArray();
        selection =
            _firstXmlText(blocks[index.clamp(0, blocks.length - 1).toInt()]);
      }
    });
    return selection;
  }

  yjs.YXmlText? _firstXmlText(Object? node) {
    if (node is yjs.YXmlText) return node;
    if (node is! yjs.YXmlFragment) return null;
    for (final child in node.toArray()) {
      final text = _firstXmlText(child);
      if (text != null) return text;
    }
    return null;
  }

  bool _supportsBlockBackground(yjs.YXmlElement block) =>
      richDocumentBlockBackgroundTypes.contains(block.name);

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

  void _replaceTextRange(
    yjs.YText text,
    String current,
    String next, {
    Map<String, Object?> attributes = const {},
  }) {
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
    String current,
    String next,
  ) {
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
      currentRunes.skip(currentRunes.length - suffixRunes),
    ).length;
    final nextSuffix = String.fromCharCodes(
      nextRunes.skip(nextRunes.length - suffixRunes),
    ).length;
    final deleteLength = current.length - prefix - currentSuffix;
    final insertion = next.substring(prefix, next.length - nextSuffix);
    return (prefix: prefix, deleteLength: deleteLength, insertion: insertion);
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

  void _onDocumentUpdate(
    dynamic update, [
    dynamic origin,
    dynamic _,
    dynamic __,
  ]) {
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

class _RichTableSelection {
  const _RichTableSelection({
    required this.table,
    required this.row,
    required this.rows,
    required this.cells,
    required this.rowIndex,
    required this.columnIndex,
  });

  final yjs.YXmlElement table;
  final yjs.YXmlElement row;
  final List<yjs.YXmlElement> rows;
  final List<yjs.YXmlElement> cells;
  final int rowIndex;
  final int columnIndex;
}

const yjsMessageSync = yjs.messageSyncStep1;
