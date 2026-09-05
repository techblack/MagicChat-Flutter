import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../data/asr_realtime.dart';
import '../../data/voice_recorder.dart';
import 'voice_message_player.dart';

typedef VoiceTranscriberFactory = VoiceTranscriber Function();

enum VoiceComposerResultKind { voice, text }

class VoiceComposerResult {
  const VoiceComposerResult.voice(this.recording, this.text)
      : kind = VoiceComposerResultKind.voice;

  const VoiceComposerResult.text(this.text)
      : kind = VoiceComposerResultKind.text,
        recording = null;

  final VoiceComposerResultKind kind;
  final RecordedVoice? recording;
  final String text;
}

enum VoiceComposerStatus {
  idle,
  requesting,
  recording,
  processing,
  transcribing,
  recorded,
}

class VoiceMessageComposerSheet extends StatefulWidget {
  const VoiceMessageComposerSheet({
    this.recorder,
    this.transcriberFactory,
    super.key,
  });

  final VoiceRecordingController? recorder;
  final VoiceTranscriberFactory? transcriberFactory;

  @override
  State<VoiceMessageComposerSheet> createState() =>
      _VoiceMessageComposerSheetState();
}

class _VoiceMessageComposerSheetState extends State<VoiceMessageComposerSheet> {
  late final VoiceRecordingController _recorder =
      widget.recorder ?? VoiceRecorder();
  late final bool _ownsRecorder = widget.recorder == null;
  StreamSubscription<String>? _transcriptSubscription;
  StreamSubscription<Uint8List>? _pcmSubscription;
  Future<void>? _transcriberConnection;
  VoiceTranscriber? _transcriber;
  Timer? _elapsedTimer;
  Timer? _maximumTimer;
  DateTime? _startedAt;
  RecordedVoice? _recording;
  VoiceComposerStatus _status = VoiceComposerStatus.idle;
  String _transcript = '';
  String? _error;
  String? _transcriptionError;
  bool _stopRequested = false;
  bool _transcriberFailed = false;

  int get _elapsedMs {
    final startedAt = _startedAt;
    if (_status == VoiceComposerStatus.recording && startedAt != null) {
      return DateTime.now()
          .difference(startedAt)
          .inMilliseconds
          .clamp(0, voiceMessageMaxDuration.inMilliseconds);
    }
    return _recording?.durationMs ?? 0;
  }

  Future<void> _startRecording() async {
    if (_status != VoiceComposerStatus.idle &&
        _status != VoiceComposerStatus.recorded) {
      return;
    }
    _stopRequested = false;
    _recording = null;
    _transcript = '';
    _error = null;
    _transcriptionError = null;
    _transcriberFailed = false;
    setState(() => _status = VoiceComposerStatus.requesting);

    final transcriber = widget.transcriberFactory?.call();
    if (transcriber != null) {
      _transcriber = transcriber;
      _transcriptSubscription = transcriber.transcripts.listen((text) {
        if (mounted) setState(() => _transcript = text.trim());
      }, onError: (Object error) {
        _failTranscription(_errorText(error));
      });
      final connection = transcriber.connect();
      _transcriberConnection = connection;
      unawaited(connection.catchError((Object error) {
        _failTranscription(_errorText(error));
      }));
    }

    try {
      final pcm = await _recorder.start();
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      _startedAt = DateTime.now();
      if (pcm != null && transcriber != null) {
        _pcmSubscription = pcm.listen((bytes) {
          if (_transcriberFailed) return;
          try {
            transcriber.sendAudio(bytes);
          } catch (error) {
            _failTranscription(_errorText(error));
          }
        }, onError: (Object error) {
          _failTranscription(_errorText(error));
        });
      } else if (transcriber != null) {
        _failTranscription('当前设备无法同时采集语音识别音频');
      }
      setState(() => _status = VoiceComposerStatus.recording);
      _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted && _status == VoiceComposerStatus.recording) {
          setState(() {});
        }
      });
      _maximumTimer = Timer(voiceMessageMaxDuration, () {
        unawaited(_stopRecording());
      });
      if (_stopRequested) await _stopRecording();
    } catch (error) {
      await _closeTranscriber();
      if (mounted) {
        setState(() {
          _status = VoiceComposerStatus.idle;
          _error = _errorText(error);
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    _stopRequested = true;
    if (_status == VoiceComposerStatus.requesting ||
        _status != VoiceComposerStatus.recording) {
      return;
    }
    _elapsedTimer?.cancel();
    _maximumTimer?.cancel();
    _elapsedTimer = null;
    _maximumTimer = null;
    setState(() => _status = VoiceComposerStatus.processing);
    try {
      final recording = await _recorder.stop();
      if (recording == null) throw StateError('没有生成有效的语音文件');
      _recording = recording;
      unawaited(_pcmSubscription?.cancel());
      _pcmSubscription = null;

      final transcriber = _transcriber;
      if (transcriber != null && !_transcriberFailed) {
        setState(() => _status = VoiceComposerStatus.transcribing);
        try {
          await _transcriberConnection;
          final completed = await transcriber.commit();
          if (completed.trim().isNotEmpty) _transcript = completed.trim();
        } catch (error) {
          _failTranscription(_errorText(error));
        }
      }
      await _closeTranscriber();
      if (mounted) setState(() => _status = VoiceComposerStatus.recorded);
    } catch (error) {
      await _closeTranscriber();
      if (mounted) {
        setState(() {
          _status = VoiceComposerStatus.idle;
          _recording = null;
          _error = _errorText(error);
        });
      }
    } finally {
      _startedAt = null;
    }
  }

  void _failTranscription(String message) {
    if (_transcriberFailed) return;
    _transcriberFailed = true;
    if (mounted) setState(() => _transcriptionError = message);
    unawaited(_closeTranscriber());
  }

  Future<void> _closeTranscriber() async {
    _transcriberConnection = null;
    unawaited(_transcriptSubscription?.cancel());
    _transcriptSubscription = null;
    unawaited(_transcriber?.close());
    _transcriber = null;
  }

  Future<void> _cancel() async {
    _elapsedTimer?.cancel();
    _maximumTimer?.cancel();
    if (_recorder.isRecording) await _recorder.cancel();
    await _closeTranscriber();
    if (mounted) Navigator.pop(context);
  }

  void _reset() {
    setState(() {
      _status = VoiceComposerStatus.idle;
      _recording = null;
      _transcript = '';
      _error = null;
      _transcriptionError = null;
      _stopRequested = false;
    });
  }

  void _sendVoice() {
    final recording = _recording;
    if (recording == null) return;
    Navigator.pop(
        context, VoiceComposerResult.voice(recording, _transcript.trim()));
  }

  void _sendText() {
    final text = _transcript.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, VoiceComposerResult.text(text));
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _maximumTimer?.cancel();
    unawaited(_pcmSubscription?.cancel());
    unawaited(_transcriptSubscription?.cancel());
    if (_recorder.isRecording) unawaited(_recorder.cancel());
    unawaited(_transcriber?.close());
    if (_ownsRecorder) unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = _status == VoiceComposerStatus.requesting ||
        _status == VoiceComposerStatus.processing ||
        _status == VoiceComposerStatus.transcribing;
    final recorded =
        _status == VoiceComposerStatus.recorded && _recording != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text('语音输入',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: '关闭',
                    onPressed: busy ? null : _cancel,
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 150),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _status == VoiceComposerStatus.recording
                      ? colors.errorContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (recorded)
                        _RecordingPreviewButton(
                            bytes: _recording!.bytes, disabled: busy)
                      else
                        Icon(Icons.graphic_eq,
                            size: 42,
                            color: _status == VoiceComposerStatus.recording
                                ? colors.error
                                : colors.primary),
                      const SizedBox(height: 10),
                      Text(_statusText(),
                          key: const ValueKey('voice-composer-status'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (_transcript.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(_transcript,
                            key: const ValueKey('voice-composer-transcript'),
                            textAlign: TextAlign.center,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis),
                      ] else if (_status ==
                          VoiceComposerStatus.transcribing) ...[
                        const SizedBox(height: 12),
                        const Text('正在识别语音内容…'),
                      ],
                    ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    key: const ValueKey('voice-composer-error'),
                    style: TextStyle(color: colors.error)),
              ],
              if (_transcriptionError != null) ...[
                const SizedBox(height: 10),
                Text('${_transcriptionError!}，仍可发送语音',
                    key: const ValueKey('voice-transcription-error'),
                    style: TextStyle(color: colors.onSurfaceVariant)),
              ],
              const SizedBox(height: 16),
              if (!recorded)
                Semantics(
                  button: true,
                  label: '按住说话',
                  hint: '按住开始录音，松开结束录音',
                  onTap: _status == VoiceComposerStatus.recording
                      ? _stopRecording
                      : _startRecording,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (_) => unawaited(_stopRecording()),
                    onLongPressEnd: (_) => unawaited(_stopRecording()),
                    child: Listener(
                      onPointerDown:
                          busy ? null : (_) => unawaited(_startRecording()),
                      onPointerUp: (_) => unawaited(_stopRecording()),
                      onPointerCancel: (_) => unawaited(_stopRecording()),
                      child: Container(
                        key: const ValueKey('voice-record-button'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _status == VoiceComposerStatus.recording
                              ? '松开结束录音'
                              : busy
                                  ? '正在准备…'
                                  : '按住说话',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Column(children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: _sendVoice,
                        icon: const Icon(Icons.mic_none),
                        label: const Text('发送语音')),
                  ),
                  if (_transcript.trim().isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                          onPressed: _sendText,
                          icon: const Icon(Icons.text_fields),
                          label: const Text('发送文本')),
                    ),
                  TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新录制')),
                ]),
            ]),
          ),
        ),
      ),
    );
  }

  String _statusText() => switch (_status) {
        VoiceComposerStatus.idle => '按住下方按钮开始录音',
        VoiceComposerStatus.requesting => '正在准备麦克风和语音识别',
        VoiceComposerStatus.recording =>
          '正在录音 ${formatVoiceDuration(_elapsedMs)}',
        VoiceComposerStatus.processing => '正在生成语音',
        VoiceComposerStatus.transcribing => '正在完成语音识别',
        VoiceComposerStatus.recorded =>
          '语音 ${formatVoiceDuration(_recording?.durationMs ?? 0)}',
      };

  String _errorText(Object error) {
    final value = error.toString().trim();
    return value.isEmpty ? '录音失败，请重新尝试' : value;
  }
}

class _RecordingPreviewButton extends StatefulWidget {
  const _RecordingPreviewButton({required this.bytes, required this.disabled});

  final Uint8List bytes;
  final bool disabled;

  @override
  State<_RecordingPreviewButton> createState() =>
      _RecordingPreviewButtonState();
}

class _RecordingPreviewButtonState extends State<_RecordingPreviewButton> {
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(widget.bytes));
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        key: const ValueKey('voice-recording-preview'),
        tooltip: _playing ? '暂停录音预览' : '播放录音预览',
        onPressed: widget.disabled ? null : _toggle,
        icon: Icon(_playing ? Icons.pause : Icons.multitrack_audio, size: 30),
      );
}
