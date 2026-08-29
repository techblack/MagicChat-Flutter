import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// 聊天中的语音播放器：只在用户点击时读取临时地址，并保证同一时间只有
/// 一条语音播放，行为与 Web/Mobile 客户端保持一致。
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    required this.fileId,
    required this.durationMs,
    required this.resolveUrl,
    this.transcript = '',
    this.foregroundColor,
    super.key,
  });

  final String fileId;
  final int durationMs;
  final String transcript;
  final Future<Uri?> Function(String fileId) resolveUrl;
  final Color? foregroundColor;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  static _VoiceMessagePlayerState? _active;

  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;
  Future<Uri?>? _urlFuture;
  String? _loadedUrl;
  bool _loading = false;
  bool _playing = false;
  bool _expanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (identical(_active, this)) _active = null;
      if (mounted) {
        setState(() {
          _playing = false;
          _loadedUrl = null;
        });
      }
    });
  }

  Future<void> _pauseForAnother() async {
    await _player.pause();
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _togglePlayback() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await (_urlFuture ??=
          widget.resolveUrl(widget.fileId).catchError((error) {
        _urlFuture = null;
        throw error;
      }));
      if (url == null || (url.scheme != 'http' && url.scheme != 'https')) {
        throw const FormatException('语音地址无效');
      }
      if (!mounted) return;
      if (!identical(_active, this)) {
        await _active?._pauseForAnother();
        _active = this;
      }
      await _player.setReleaseMode(ReleaseMode.stop);
      if (_loadedUrl != url.toString()) {
        await _player.setSourceUrl(url.toString());
        _loadedUrl = url.toString();
      }
      await _player.resume();
    } catch (_) {
      if (identical(_active, this)) _active = null;
      if (mounted) {
        setState(() {
          _error = '加载失败';
          _playing = false;
        });
      }
      _loadedUrl = null;
      _urlFuture = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant VoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _loadedUrl = null;
      _urlFuture = null;
      _error = null;
      _playing = false;
    }
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    unawaited(_stateSubscription?.cancel());
    unawaited(_completeSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final foreground = widget.foregroundColor ?? color;
    final duration = formatVoiceDuration(widget.durationMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.multitrack_audio, size: 20, color: foreground),
            const SizedBox(width: 8),
            Text('语音 $duration', style: TextStyle(color: foreground)),
            const SizedBox(width: 6),
            IconButton(
              tooltip: _playing ? '暂停语音' : '播放语音',
              onPressed: _loading ? null : _togglePlayback,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_playing ? Icons.pause : Icons.play_arrow,
                      color: foreground),
              color: foreground,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (widget.transcript.trim().isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              widget.transcript.trim(),
              style: TextStyle(color: foreground),
              maxLines: _expanded ? null : 1,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
          ),
      ],
    );
  }
}

String formatVoiceDuration(int durationMs) {
  final totalSeconds = durationMs <= 0 ? 1 : (durationMs / 1000).ceil();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

int parseVoiceDuration(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value <= 0 ||
      value > 60000 ||
      value % 1 != 0) {
    return 0;
  }
  return value.toInt();
}
