import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_recording_file.dart';

const voiceMessageMaxDuration = Duration(seconds: 60);
const voiceMessageMinDuration = Duration(milliseconds: 500);
const voiceMessageMaxBytes = 1024 * 1024;

abstract interface class VoiceRecordingController {
  bool get isRecording;
  Future<Stream<Uint8List>?> start();
  Future<RecordedVoice?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class RecordedVoice {
  const RecordedVoice({
    required this.bytes,
    required this.durationMs,
    required this.mimeType,
    required this.name,
  });

  final Uint8List bytes;
  final int durationMs;
  final String mimeType;
  final String name;
}

/// 主录音生成可发送的压缩文件，第二路 16kHz 单声道 PCM 尽力提供给
/// 实时语音识别；设备不允许并行采集时仍可正常发送语音。
class VoiceRecorder implements VoiceRecordingController {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioRecorder _pcmRecorder = AudioRecorder();
  String? _path;
  DateTime? _startedAt;

  @override
  bool get isRecording => _path != null;

  @override
  Future<Stream<Uint8List>?> start() async {
    if (_path != null) return null;
    if (!await _recorder.hasPermission()) {
      throw const VoicePermissionDenied();
    }
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}/magicchat-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    const config = RecordConfig(
      encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
      bitRate: kIsWeb ? 24000 : 32000,
      sampleRate: kIsWeb ? 48000 : 44100,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    );
    await _recorder.start(config, path: path);
    _path = path;
    _startedAt = DateTime.now();

    try {
      return await _pcmRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        streamBufferSize: 3200,
      ));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RecordedVoice?> stop() async {
    final initialPath = _path;
    if (initialPath == null) return null;
    final startedAt = _startedAt;
    _path = null;
    _startedAt = null;
    try {
      try {
        await _pcmRecorder.stop();
      } catch (_) {
        // PCM 是可选识别支路，停止失败不丢弃已录制语音。
      }
      final outputPath = await _recorder.stop() ?? initialPath;
      final duration = startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt);
      final durationMs = duration.inMilliseconds
          .clamp(1, voiceMessageMaxDuration.inMilliseconds);
      if (durationMs < voiceMessageMinDuration.inMilliseconds) {
        await deleteVoiceRecordingFile(outputPath);
        throw const VoiceRecordingException('录音时间太短，请重新录制');
      }
      final bytes = await readVoiceRecordingBytes(outputPath);
      await deleteVoiceRecordingFile(outputPath);
      if (bytes == null || bytes.isEmpty) {
        throw const VoiceRecordingException('没有录制到有效的语音内容');
      }
      if (bytes.length > voiceMessageMaxBytes) {
        throw const VoiceRecordingException('语音文件超过 1 MiB，请重新录制');
      }
      return RecordedVoice(
        bytes: bytes,
        durationMs: durationMs,
        mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        name: kIsWeb ? 'voice-message.webm' : 'voice-message.m4a',
      );
    } catch (_) {
      await deleteVoiceRecordingFile(initialPath);
      rethrow;
    }
  }

  @override
  Future<void> cancel() async {
    _path = null;
    _startedAt = null;
    try {
      await _pcmRecorder.cancel();
    } catch (_) {
      // 可选识别支路可能没有启动。
    }
    await _recorder.cancel();
  }

  @override
  Future<void> dispose() async {
    if (_path != null) await cancel();
    await _pcmRecorder.dispose();
    await _recorder.dispose();
  }
}

class VoicePermissionDenied implements Exception {
  const VoicePermissionDenied();

  @override
  String toString() => '需要麦克风权限才能录制语音';
}

class VoiceRecordingException implements Exception {
  const VoiceRecordingException(this.message);

  final String message;

  @override
  String toString() => message;
}
