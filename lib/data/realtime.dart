import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 对齐现有 `/api/client/ws` envelope/cursor 语义，页面可订阅增量事件。
class MagicChatRealtime {
  MagicChatRealtime(
      {required String serverUrl,
      required this.sessionToken,
      required this.connector})
      : _uri = _buildUri(serverUrl);
  final Uri _uri;
  final String sessionToken;

  /// 平台适配层负责建立连接：Native 使用 Authorization header，Web 使用
  /// 浏览器自动携带的 user_session Cookie。
  final WebSocketConnector connector;
  WebSocketChannel? _channel;

  Stream<Map<String, dynamic>> connect({int? cursor}) {
    final query = <String, String>{};
    if (cursor != null) query['cursor'] = '$cursor';
    final uri = _uri.replace(queryParameters: query);
    final channel = connector(uri, sessionToken);
    _channel = channel;
    return channel.stream.cast<String>().map((event) {
      final value = jsonDecode(event);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('实时事件格式不正确');
      }
      return value;
    });
  }

  Future<void> send(Map<String, dynamic> envelope) async {
    final channel = _channel;
    if (channel == null) throw StateError('实时连接尚未建立');
    await channel.ready;
    channel.sink.add(jsonEncode(envelope));
  }

  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  static Uri _buildUri(String serverUrl) {
    final base = Uri.parse(serverUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(
        scheme: scheme,
        path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/api/client/ws');
  }
}

typedef WebSocketConnector = WebSocketChannel Function(
    Uri uri, String sessionToken);

enum RealtimeStatus { disconnected, connecting, connected, reconnecting }

/// 管理实时连接生命周期；重复、乱序事件交由上层按 envelope/cursor 幂等投影。
class RealtimeSession {
  RealtimeSession(
      {required this.realtime,
      this.delays = const [500, 1000, 2000, 5000, 10000, 30000]});
  final MagicChatRealtime realtime;
  final List<int> delays;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _pendingRequests = <String, _PendingRealtimeRequest>{};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _retry;
  RealtimeStatus status = RealtimeStatus.disconnected;
  bool ready = false;
  int _cursor = 0;
  int _attempt = 0;
  int? _reconnectDelayMs;
  int _requestSequence = 0;
  bool _closed = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  int get cursor => _cursor;
  int get reconnectAttempt => _attempt;
  int? get reconnectDelayMs =>
      _retry?.isActive == true ? _reconnectDelayMs : null;

  Future<void> connect({int cursor = 0}) async {
    _cursor = cursor;
    _closed = false;
    _retry?.cancel();
    await _open();
  }

  /// 手动重试当前连接，沿用已确认的 cursor，避免刷新时重复同步历史事件。
  Future<void> reconnect() async {
    if (_closed) return;
    _retry?.cancel();
    _attempt = 0;
    await _open();
  }

  Future<void> _open() async {
    if (_closed) return;
    _reconnectDelayMs = null;
    ready = false;
    status =
        _attempt == 0 ? RealtimeStatus.connecting : RealtimeStatus.reconnecting;
    await _subscription?.cancel();
    try {
      _subscription = realtime
          .connect(cursor: _cursor == 0 ? null : _cursor)
          .listen(_onEvent,
              onError: (_) => _scheduleRetry(), onDone: _scheduleRetry);
      status = RealtimeStatus.connected;
      _attempt = 0;
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    final replyTo = event['reply_to'];
    if ((event['kind'] == 'response' || replyTo is String) &&
        replyTo is String) {
      final pending = _pendingRequests.remove(replyTo);
      if (pending == null) return;
      pending.timer.cancel();
      if (event['ok'] == true) {
        pending.completer.complete(event['payload']);
      } else {
        final error = event['error'];
        final message = error is Map<String, dynamic> &&
                error['message'] is String &&
                (error['message'] as String).trim().isNotEmpty
            ? (error['message'] as String).trim()
            : '实时请求失败';
        pending.completer.completeError(RealtimeRequestException(message));
      }
      return;
    }
    final cursor = event['cursor'];
    if (cursor is num && cursor.toInt() > _cursor) _cursor = cursor.toInt();
    if (event['event'] == 'system.ready') ready = true;
    _events.add(event);
  }

  Future<dynamic> sendRequest(String method, Map<String, dynamic> payload,
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (_closed || !ready || status != RealtimeStatus.connected) {
      throw StateError('实时连接尚未就绪');
    }
    final requestId =
        'flutter-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
    final completer = Completer<dynamic>();
    final timer = Timer(timeout, () {
      final pending = _pendingRequests.remove(requestId);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(TimeoutException('实时请求超时', timeout));
      }
    });
    _pendingRequests[requestId] = _PendingRealtimeRequest(completer, timer);
    try {
      await realtime.send({
        'v': 1,
        'kind': 'request',
        'id': requestId,
        'method': method,
        'payload': payload,
      });
    } catch (error, stackTrace) {
      final pending = _pendingRequests.remove(requestId);
      pending?.timer.cancel();
      Error.throwWithStackTrace(error, stackTrace);
    }
    return completer.future;
  }

  void _scheduleRetry() {
    if (_closed || _retry?.isActive == true) return;
    ready = false;
    _rejectPending(StateError('实时连接已断开'));
    _events.add(const {
      'event': 'system.connection_lost',
      'payload': <String, dynamic>{},
    });
    status = RealtimeStatus.reconnecting;
    final delay = delays.isEmpty
        ? 1000
        : delays[_attempt.clamp(0, delays.length - 1).toInt()];
    _attempt++;
    _reconnectDelayMs = delay;
    _retry = Timer(Duration(milliseconds: delay), _open);
  }

  Future<void> close() async {
    _closed = true;
    ready = false;
    _retry?.cancel();
    _reconnectDelayMs = null;
    _rejectPending(StateError('实时连接已关闭'));
    await _subscription?.cancel();
    await realtime.close();
    status = RealtimeStatus.disconnected;
    await _events.close();
  }

  void _rejectPending(Object error) {
    for (final pending in _pendingRequests.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _pendingRequests.clear();
  }
}

class RealtimeRequestException implements Exception {
  const RealtimeRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PendingRealtimeRequest {
  const _PendingRealtimeRequest(this.completer, this.timer);

  final Completer<dynamic> completer;
  final Timer timer;
}
