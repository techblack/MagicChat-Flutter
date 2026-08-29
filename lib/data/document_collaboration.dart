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
  }

  final String documentId;
  final String documentType;
  final DocumentRealtime _realtime;
  final yjs.Doc _document;
  late final yjs.Awareness _awareness;
  late final yjs.YText _markdown;
  late final yjs.YXmlFragment _body;
  StreamSubscription<Uint8List>? _subscription;
  DocumentCollaborationStatus status = DocumentCollaborationStatus.disconnected;
  bool _closed = false;
  bool _authenticated = false;

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

  void setPresence(Map<String, Object?> state) {
    if (_closed) return;
    _awareness.setLocalState(state);
  }

  Future<void> connect() async {
    _closed = false;
    _authenticated = false;
    status = DocumentCollaborationStatus.connecting;
    notifyListeners();
    _document.on('update', _onDocumentUpdate);
    _awareness.on('update', _onAwarenessUpdate);
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

  void replaceText(String value) {
    if (status != DocumentCollaborationStatus.synced || value == text) {
      return;
    }
    final oldText = text;
    _document.transact((_) {
      if (documentType == 'markdown') {
        // Remote Y.Text content may span several items in the Dart binding.
        // Replacing the complete value avoids partial-split index issues while
        // still emitting one Yjs transaction on the wire.
        if (oldText.isNotEmpty) _markdown.delete(0, oldText.length);
        if (value.isNotEmpty) _markdown.insert(0, value);
      } else {
        _replaceBodyText(value);
      }
    });
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
      if (node.length > 0) node.delete(0, node.length);
      if (next.isNotEmpty) node.insert(0, next);
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
