import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/asr_realtime.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/voice_recorder.dart';
import 'package:magicchat_client/features/messages/voice_message_composer_sheet.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('聊天输入区通过语音入口打开按住说话面板', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: DemoRepository(), conversationId: 'welcome'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('语音输入'));
    await tester.pumpAndSettle();

    expect(find.byType(VoiceMessageComposerSheet), findsOneWidget);
    expect(find.text('语音输入'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-record-button')), findsOneWidget);
    expect(find.text('按住说话'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceMessageComposerSheet), findsNothing);
  });

  testWidgets('按住录音并识别后可发送带文字的语音', (tester) async {
    final recorder = _FakeRecorder();
    final transcriber = _FakeTranscriber(completedText: '最终识别文字');
    VoiceComposerResult? result;
    await _pumpSheet(tester,
        recorder: recorder,
        transcriberFactory: () => transcriber,
        onResult: (value) => result = value);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('voice-record-button'))));
    await tester.pump();
    recorder.emit(Uint8List.fromList([1, 2, 3, 4]));
    transcriber.emitTranscript('实时识别');
    await tester.pump();
    expect(find.text('实时识别'), findsOneWidget);
    expect(find.textContaining('正在录音'), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(transcriber.audio, [1, 2, 3, 4]);
    expect(recorder.isRecording, isFalse);
    expect(recorder.stopCompleted, isTrue);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('voice-composer-status')))
            .data,
        '语音 00:02');
    expect(find.text('发送语音'), findsOneWidget);
    expect(transcriber.committed, isTrue);
    expect(find.text('最终识别文字'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('voice-recording-preview')), findsOneWidget);
    expect(find.text('发送语音'), findsOneWidget);
    expect(find.text('发送文本'), findsOneWidget);

    await tester.tap(find.text('发送语音'));
    await tester.pumpAndSettle();
    expect(result?.kind, VoiceComposerResultKind.voice);
    expect(result?.text, '最终识别文字');
    expect(result?.recording?.durationMs, 1200);
    expect(result?.recording?.bytes, [7, 8, 9]);
  });

  testWidgets('识别失败仍允许发送语音', (tester) async {
    final recorder = _FakeRecorder(withPcm: false);
    VoiceComposerResult? result;
    await _pumpSheet(tester,
        recorder: recorder,
        transcriberFactory: _FailingTranscriber.new,
        onResult: (value) => result = value);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('voice-record-button'))));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-transcription-error')),
        findsOneWidget);
    expect(find.text('发送语音'), findsOneWidget);
    expect(find.text('发送文本'), findsNothing);
    await tester.tap(find.text('发送语音'));
    await tester.pumpAndSettle();
    expect(result?.kind, VoiceComposerResultKind.voice);
  });

  testWidgets('识别完成后可直接发送文本', (tester) async {
    final recorder = _FakeRecorder();
    VoiceComposerResult? result;
    await _pumpSheet(tester,
        recorder: recorder,
        transcriberFactory: () => _FakeTranscriber(completedText: '改成文字发送'),
        onResult: (value) => result = value);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('voice-record-button'))));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送文本'));
    await tester.pumpAndSettle();

    expect(result?.kind, VoiceComposerResultKind.text);
    expect(result?.text, '改成文字发送');
    expect(result?.recording, isNull);
  });

  testWidgets('重新录制会创建新的识别会话', (tester) async {
    final recorder = _FakeRecorder();
    var sessions = 0;
    VoiceComposerResult? result;
    await _pumpSheet(tester,
        recorder: recorder,
        transcriberFactory: () =>
            _FakeTranscriber(completedText: sessions++ == 0 ? '第一次' : '第二次'),
        onResult: (value) => result = value);

    Future<void> recordOnce() async {
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('voice-record-button'))));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
    }

    await recordOnce();
    expect(find.text('第一次'), findsOneWidget);
    await tester.tap(find.text('重新录制'));
    await tester.pump();
    await recordOnce();
    expect(find.text('第二次'), findsOneWidget);
    expect(sessions, 2);

    await tester.tap(find.text('发送语音'));
    await tester.pumpAndSettle();
    expect(result?.text, '第二次');
  });

  testWidgets('录音达到 60 秒会自动结束', (tester) async {
    final recorder = _FakeRecorder(withPcm: false);
    await _pumpSheet(tester,
        recorder: recorder,
        transcriberFactory: _FailingTranscriber.new,
        onResult: (_) {});

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('voice-record-button'))));
    await tester.pump();
    expect(recorder.isRecording, isTrue);
    await tester.pump(voiceMessageMaxDuration);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(recorder.isRecording, isFalse);
    expect(find.text('发送语音'), findsOneWidget);
    await gesture.up();
  });
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required VoiceRecordingController recorder,
  required VoiceTranscriberFactory transcriberFactory,
  required ValueChanged<VoiceComposerResult> onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            final result = await showModalBottomSheet<VoiceComposerResult>(
              context: context,
              isScrollControlled: true,
              builder: (_) => VoiceMessageComposerSheet(
                recorder: recorder,
                transcriberFactory: transcriberFactory,
              ),
            );
            if (result != null) onResult(result);
          },
          child: const Text('打开语音输入'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('打开语音输入'));
  await tester.pumpAndSettle();
}

class _FakeRecorder implements VoiceRecordingController {
  _FakeRecorder({this.withPcm = true});

  final bool withPcm;
  var _pcm = StreamController<Uint8List>.broadcast(sync: true);
  @override
  bool isRecording = false;
  bool stopCompleted = false;

  void emit(Uint8List bytes) => _pcm.add(bytes);

  @override
  Future<Stream<Uint8List>?> start() async {
    isRecording = true;
    if (_pcm.isClosed) {
      _pcm = StreamController<Uint8List>.broadcast(sync: true);
    }
    return withPcm ? _pcm.stream : null;
  }

  @override
  Future<RecordedVoice?> stop() async {
    isRecording = false;
    if (!_pcm.isClosed) unawaited(_pcm.close());
    stopCompleted = true;
    return RecordedVoice(
        bytes: Uint8List.fromList([7, 8, 9]),
        durationMs: 1200,
        mimeType: 'audio/mp4',
        name: 'voice-message.m4a');
  }

  @override
  Future<void> cancel() async {
    isRecording = false;
    if (!_pcm.isClosed) unawaited(_pcm.close());
  }

  @override
  Future<void> dispose() async {}
}

class _FakeTranscriber implements VoiceTranscriber {
  _FakeTranscriber({required this.completedText});

  final String completedText;
  final _transcripts = StreamController<String>.broadcast();
  final audio = <int>[];
  bool committed = false;

  void emitTranscript(String text) => _transcripts.add(text);

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Future<void> connect() async {}

  @override
  void sendAudio(Uint8List bytes) => audio.addAll(bytes);

  @override
  Future<String> commit() async {
    committed = true;
    return completedText;
  }

  @override
  Future<void> close() async {
    if (!_transcripts.isClosed) await _transcripts.close();
  }
}

class _FailingTranscriber implements VoiceTranscriber {
  final _transcripts = StreamController<String>.broadcast();

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Future<void> connect() async => throw StateError('识别服务不可用');

  @override
  void sendAudio(Uint8List bytes) {}

  @override
  Future<String> commit() async => '';

  @override
  Future<void> close() async {
    if (!_transcripts.isClosed) await _transcripts.close();
  }
}
