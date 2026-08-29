import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

import 'document_realtime.dart';

enum DocumentCollaborationStatus { disconnected, connecting, synced, error }

/// 将 Markdown 文档绑定到服务端 Y.Text，并通过 Hocuspocus sync 帧交换更新。
/// 富文本文档需独立绑定 Y.XmlFragment("body")，不在此类中降级为 Markdown。
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
  }

  final String documentId;
  final String documentType;
  final DocumentRealtime _realtime;
  final yjs.Doc _document;
  late final yjs.Awareness _awareness;
  late final yjs.YText _markdown;
  StreamSubscription<Uint8List>? _subscription;
  DocumentCollaborationStatus status = DocumentCollaborationStatus.disconnected;
  bool _closed = false;
  bool _authenticated = false;

  String get text => _markdown.toString();

  /// 当前连接中除本机外的在线协作者数量。
  int get collaboratorCount => _awareness.states.keys
      .where((client) => client != _awareness.clientID)
      .length;

  /// 当前 Awareness 状态，供编辑器展示用户信息或光标扩展使用。
  Map<int, Map<String, Object?>> get awarenessStates =>
      Map.unmodifiable(_awareness.states);

  void setPresence(Map<String, Object?> state) {
    if (_closed || documentType != 'markdown') return;
    _awareness.setLocalState(state);
  }

  Future<void> connect() async {
    if (documentType != 'markdown') return;
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
    if (documentType != 'markdown' ||
        status != DocumentCollaborationStatus.synced ||
        value == text) {
      return;
    }
    final oldText = text;
    // Remote Y.Text content may span several items in the Dart binding.
    // Replacing the complete value avoids partial-split index issues while
    // still emitting one Yjs transaction on the wire.
    _document.transact((_) {
      if (oldText.isNotEmpty) _markdown.delete(0, oldText.length);
      if (value.isNotEmpty) _markdown.insert(0, value);
    });
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
