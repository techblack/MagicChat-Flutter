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
    _markdown = _document.getText('markdown')!;
  }

  final String documentId;
  final String documentType;
  final DocumentRealtime _realtime;
  final yjs.Doc _document;
  late final yjs.YText _markdown;
  StreamSubscription<Uint8List>? _subscription;
  DocumentCollaborationStatus status = DocumentCollaborationStatus.disconnected;
  bool _closed = false;

  String get text => _markdown.toString();

  Future<void> connect() async {
    if (documentType != 'markdown') return;
    _closed = false;
    status = DocumentCollaborationStatus.connecting;
    notifyListeners();
    _document.on('update', _onDocumentUpdate);
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

  void _onFrame(Uint8List frame) {
    if (_closed) return;
    final decoder = yjs.createDecoder(frame);
    final name = yjs.readVarString(decoder);
    if (name != documentId || !yjs.hasContent(decoder)) return;
    final type = yjs.readVarUint(decoder);
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
    _document.off('update', _onDocumentUpdate);
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
