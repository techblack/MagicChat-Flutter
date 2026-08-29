import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef DocumentSocketConnector = WebSocketChannel Function(
    Uri uri, String token);

/// Hocuspocus 协议版本。服务端当前使用 @hocuspocus/server 4.4.x。
const hocuspocusProtocolVersion = '4.4.0';

/// 文档协作二进制桥接。
///
/// 该类只负责 WebSocket 生命周期和 Hocuspocus 路由/认证握手，不解析
/// Yjs 更新。调用方仍需提供兼容 Yjs 的文档实现来读写正文；因此原生
/// Flutter 当前可以建立真实的协作连接，但不能把本地文本草稿当作共享正文。
class DocumentRealtime {
  DocumentRealtime(
      {required String serverUrl,
      required this.token,
      required this.connector,
      this.documentId,
      this.hocuspocusToken = 'session-cookie',
      this.maxFrameBytes = 16 * 1024 * 1024})
      : _uri = _buildUri(serverUrl);
  final Uri _uri;
  final String token;
  final DocumentSocketConnector connector;

  /// Hocuspocus 文档名。为空时仅建立原始 WebSocket（兼容旧调用方）。
  final String? documentId;

  /// Hocuspocus Auth 消息中的 token。服务端目前通过 HttpOnly
  /// `user_session` Cookie 鉴权，因此应发送其约定的 `session-cookie` 标记，
  /// 不要把实际会话凭据重复写入协议帧。
  final String hocuspocusToken;
  final int maxFrameBytes;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _events = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get events => _events.stream;
  bool _closed = false;
  bool _syncRequested = false;

  Future<void> connect() async {
    await _subscription?.cancel();
    _closed = false;
    _syncRequested = false;
    final channel = connector(_uri, token);
    _channel = channel;
    _subscription = channel.stream.listen(
        (value) {
          if (_closed) {
            return;
          }
          final frame = _bytes(value);
          if (frame == null || frame.isEmpty || frame.length > maxFrameBytes) {
            return;
          }
          _events.add(frame);
          if (!_syncRequested &&
              documentId != null &&
              _isAuthenticatedFrame(frame, documentId!)) {
            _syncRequested = true;
            _sendProtocolFrame(channel,
                encodeHocuspocusSyncStepOneFrame(documentName: documentId!));
          }
        },
        onError: _events.addError,
        onDone: () {
          if (!_closed) {
            _events.close();
          }
        });
    await channel.ready;
    if (_closed || documentId == null) {
      return;
    }
    final name = documentId!;
    _sendProtocolFrame(
        channel,
        encodeHocuspocusAuthenticationFrame(
            documentName: name, token: hocuspocusToken));
  }

  Future<void> send(Uint8List frame) async {
    if (_closed || frame.isEmpty || frame.length > maxFrameBytes) {
      throw StateError('文档协作帧无效');
    }
    _channel?.sink.add(frame);
  }

  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    await _events.close();
  }

  Uint8List? _bytes(dynamic value) {
    if (value is Uint8List) return Uint8List.fromList(value);
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is ByteBuffer) return Uint8List.fromList(value.asUint8List());
    return null;
  }

  static Uri _buildUri(String serverUrl) {
    final base = Uri.parse(serverUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(
        scheme: scheme,
        path:
            '${base.path.replaceFirst(RegExp(r'/$'), '')}/api/client/document/collaboration');
  }

  void _sendProtocolFrame(WebSocketChannel channel, Uint8List frame) {
    if (frame.isEmpty || frame.length > maxFrameBytes) {
      throw StateError('文档协作握手帧无效');
    }
    channel.sink.add(frame);
  }

  bool _isAuthenticatedFrame(Uint8List frame, String name) {
    final reader = _FrameReader(frame);
    return reader.string() == name &&
        reader.varUint() == HocuspocusMessageType.auth &&
        reader.varUint() == 2;
  }
}

/// Hocuspocus v4 的消息类型。
abstract final class HocuspocusMessageType {
  static const sync = 0;
  static const auth = 2;
}

/// 编码 Hocuspocus AuthenticationMessage。
///
/// 帧布局与 `@hocuspocus/provider` 4.4.0 一致：
/// `documentName, MessageType.Auth, AuthMessageType.Token, token, version`。
Uint8List encodeHocuspocusAuthenticationFrame({
  required String documentName,
  required String token,
  String version = hocuspocusProtocolVersion,
}) {
  final bytes = BytesBuilder(copy: false);
  _writeVarString(bytes, documentName);
  _writeVarUint(bytes, HocuspocusMessageType.auth);
  _writeVarUint(bytes, 0); // AuthMessageType.Token
  _writeVarString(bytes, token);
  _writeVarString(bytes, version);
  return bytes.takeBytes();
}

/// 编码服务端认证成功响应，供握手测试和兼容连接器使用。
Uint8List encodeHocuspocusAuthenticatedFrame({
  required String documentName,
  String scope = '',
}) {
  final bytes = BytesBuilder(copy: false);
  _writeVarString(bytes, documentName);
  _writeVarUint(bytes, HocuspocusMessageType.auth);
  _writeVarUint(bytes, 2); // AuthMessageType.Authenticated
  _writeVarString(bytes, scope);
  return bytes.takeBytes();
}

/// 编码 Hocuspocus SyncStepOneMessage。
///
/// 空状态向量在 Yjs wire format 中编码为单字节 `0`，表示请求完整状态。
Uint8List encodeHocuspocusSyncStepOneFrame({
  required String documentName,
  List<int> stateVector = const [0],
}) {
  final bytes = BytesBuilder(copy: false);
  _writeVarString(bytes, documentName);
  _writeVarUint(bytes, HocuspocusMessageType.sync);
  _writeVarUint(bytes, 0); // messageYjsSyncStep1
  _writeVarUint8Array(bytes, Uint8List.fromList(stateVector));
  return bytes.takeBytes();
}

void _writeVarUint(BytesBuilder bytes, int value) {
  if (value < 0) throw ArgumentError.value(value, 'value');
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) byte |= 0x80;
    bytes.addByte(byte);
  } while (remaining != 0);
}

void _writeVarString(BytesBuilder bytes, String value) {
  final encoded = Uint8List.fromList(utf8.encode(value));
  _writeVarUint8Array(bytes, encoded);
}

void _writeVarUint8Array(BytesBuilder bytes, Uint8List value) {
  _writeVarUint(bytes, value.length);
  bytes.add(value);
}

class _FrameReader {
  _FrameReader(this._frame);
  final Uint8List _frame;
  var _offset = 0;

  int varUint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = _frame[_offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return value;
      shift += 7;
    }
  }

  String string() {
    final length = varUint();
    final value = Uint8List.sublistView(_frame, _offset, _offset + length);
    _offset += length;
    return utf8.decode(value);
  }
}
