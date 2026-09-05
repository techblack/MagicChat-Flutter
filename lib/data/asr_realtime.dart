import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime.dart';

abstract interface class VoiceTranscriber {
  Stream<String> get transcripts;
  Future<void> connect();
  void sendAudio(Uint8List bytes);
  Future<String> commit();
  Future<void> close();
}

enum AsrRealtimeState {
  disconnected,
  connecting,
  recognizing,
  committed,
  completed,
  failed,
}

class AsrRealtimeClient implements VoiceTranscriber {
  AsrRealtimeClient({
    required String serverUrl,
    required this.sessionToken,
    required this.connector,
    this.connectTimeout = const Duration(seconds: 10),
    this.completionTimeout = const Duration(seconds: 15),
  }) : uri = buildAsrWebSocketUri(serverUrl);

  static const _maxFrameBytes = 64 * 1024;
  static const _maxQueuedBytes = 2 * 1024 * 1024;

  final Uri uri;
  final String sessionToken;
  final WebSocketConnector connector;
  final Duration connectTimeout;
  final Duration completionTimeout;
  final _transcripts = StreamController<String>.broadcast(sync: true);
  final _queuedAudio = <Uint8List>[];
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Completer<void>? _ready;
  Completer<String>? _completed;
  int _queuedBytes = 0;
  bool _closed = false;
  AsrRealtimeState state = AsrRealtimeState.disconnected;

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Future<void> connect() async {
    if (_channel != null || state == AsrRealtimeState.connecting) {
      throw StateError('语音识别连接已经建立');
    }
    _closed = false;
    state = AsrRealtimeState.connecting;
    final ready = _ready = Completer<void>();
    final channel = connector(uri, sessionToken);
    _channel = channel;
    _subscription = channel.stream.listen(_onMessage,
        onError: (Object error, StackTrace stackTrace) =>
            _fail(_errorText(error), stackTrace),
        onDone: () {
          if (!_closed && state != AsrRealtimeState.completed) {
            _fail('语音识别连接已断开');
          }
        });
    try {
      await channel.ready;
      await ready.future.timeout(connectTimeout,
          onTimeout: () => throw TimeoutException('连接语音识别服务超时'));
    } catch (error, stackTrace) {
      _fail(_errorText(error), stackTrace);
      rethrow;
    }
  }

  @override
  void sendAudio(Uint8List bytes) {
    if (bytes.isEmpty) return;
    if (bytes.length.isOdd) {
      throw const AsrRealtimeException('语音数据格式错误');
    }
    if (state != AsrRealtimeState.connecting &&
        state != AsrRealtimeState.recognizing) {
      throw const AsrRealtimeException('语音识别尚未准备好');
    }
    for (var offset = 0; offset < bytes.length; offset += _maxFrameBytes) {
      var end = (offset + _maxFrameBytes).clamp(0, bytes.length);
      if ((end - offset).isOdd) end--;
      final frame = Uint8List.sublistView(bytes, offset, end);
      if (state == AsrRealtimeState.recognizing) {
        _channel!.sink.add(frame);
      } else {
        if (_queuedBytes + frame.length > _maxQueuedBytes) {
          _fail('语音识别发送速度过慢');
          throw const AsrRealtimeException('语音识别发送速度过慢');
        }
        final copy = Uint8List.fromList(frame);
        _queuedAudio.add(copy);
        _queuedBytes += copy.length;
      }
    }
  }

  @override
  Future<String> commit() async {
    if (state != AsrRealtimeState.recognizing) {
      throw const AsrRealtimeException('语音识别尚未准备好');
    }
    state = AsrRealtimeState.committed;
    final completed = _completed = Completer<String>();
    _channel!.sink.add(jsonEncode(const {'type': 'commit'}));
    try {
      return await completed.future.timeout(completionTimeout,
          onTimeout: () => throw TimeoutException('语音识别响应超时'));
    } catch (error, stackTrace) {
      _fail(_errorText(error), stackTrace);
      rethrow;
    }
  }

  void _onMessage(Object? raw) {
    if (raw is! String) {
      _fail('语音识别服务返回了无效数据');
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      _fail('语音识别服务返回了无效数据');
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      _fail('语音识别服务返回了无效数据');
      return;
    }
    switch (decoded['type']) {
      case 'ready':
        if (state != AsrRealtimeState.connecting) return;
        state = AsrRealtimeState.recognizing;
        _ready?.complete();
        _ready = null;
        for (final frame in _queuedAudio) {
          _channel!.sink.add(frame);
        }
        _queuedAudio.clear();
        _queuedBytes = 0;
        return;
      case 'transcript':
        if (decoded['text'] is String) {
          _transcripts.add(decoded['text'] as String);
        }
        return;
      case 'completed':
        final text = decoded['text'] is String ? decoded['text'] as String : '';
        state = AsrRealtimeState.completed;
        if (_completed?.isCompleted == false) _completed!.complete(text);
        return;
      case 'error':
        final message = decoded['message'] is String &&
                (decoded['message'] as String).trim().isNotEmpty
            ? (decoded['message'] as String).trim()
            : '语音识别失败';
        _fail(message);
        return;
      default:
        _fail('语音识别服务返回了无效数据');
        return;
    }
  }

  void _fail(String message, [StackTrace? stackTrace]) {
    if (state == AsrRealtimeState.failed || _closed) return;
    state = AsrRealtimeState.failed;
    final error = AsrRealtimeException(message);
    if (_ready?.isCompleted == false) {
      _ready!.completeError(error, stackTrace);
    }
    if (_completed?.isCompleted == false) {
      _completed!.completeError(error, stackTrace);
    }
    _ready = null;
    _completed = null;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    if (state != AsrRealtimeState.completed) {
      _fail('语音识别连接已关闭');
    }
    _closed = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _queuedAudio.clear();
    _queuedBytes = 0;
    await _transcripts.close();
    if (state != AsrRealtimeState.completed) {
      state = AsrRealtimeState.disconnected;
    }
  }

  String _errorText(Object error) => error is TimeoutException
      ? error.message ?? '语音识别超时'
      : error is AsrRealtimeException
          ? error.message
          : '无法连接语音识别服务';
}

Uri buildAsrWebSocketUri(String serverUrl) {
  final base =
      Uri.parse('${serverUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/');
  final uri = base.resolve('api/client/asr/realtime');
  return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
}

class AsrRealtimeException implements Exception {
  const AsrRealtimeException(this.message);

  final String message;

  @override
  String toString() => message;
}
