import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/features/messages/voice_message_player.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('formats voice duration using the shared client convention', () {
    expect(formatVoiceDuration(1), '00:01');
    expect(formatVoiceDuration(2001), '00:03');
    expect(formatVoiceDuration(61000), '01:01');
    expect(formatVoiceDuration(90 * 60 * 1000), '90:00');
  });

  test('parses only positive integral server durations', () {
    expect(parseVoiceDuration(1500), 1500);
    expect(parseVoiceDuration(0), 0);
    expect(parseVoiceDuration(-1), 0);
    expect(parseVoiceDuration('1500'), 0);
    expect(parseVoiceDuration(double.nan), 0);
    expect(parseVoiceDuration(60001), 0);
  });

  test('sends the recorded duration and transcript in the voice multipart form',
      () async {
    late http.BaseRequest request;
    late String multipartBody;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient.streaming((value, body) async {
        request = value;
        multipartBody = utf8.decode(await body.toBytes());
        return http.StreamedResponse(
          http.ByteStream.fromBytes(const []),
          200,
        );
      }),
    );

    await repository.sendVoice(
      'conversation-1',
      AttachmentUpload(
        path: '',
        name: 'voice.m4a',
        mimeType: 'audio/mp4',
        bytes: Uint8List.fromList([0, 1, 2]),
      ),
      durationMs: 3200,
      transcript: '测试转录',
    );

    expect(request.method, 'POST');
    expect(multipartBody, contains('name="duration_ms"'));
    expect(multipartBody, contains('\r\n\r\n3200\r\n'));
    expect(multipartBody, contains('name="transcript"'));
    expect(multipartBody, contains('\r\n\r\n测试转录\r\n'));
    expect(multipartBody, contains('name="voice"'));
  });

  testWidgets('renders duration and collapsible transcript', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VoiceMessagePlayer(
          fileId: 'voice-1',
          durationMs: 3200,
          transcript: '第一行转录内容，第二行转录内容',
          resolveUrl: (_) async => Uri.parse('https://example.com/voice.m4a'),
        ),
      ),
    ));

    expect(find.text('语音 00:04'), findsOneWidget);
    expect(find.text('第一行转录内容，第二行转录内容'), findsOneWidget);
    expect(find.byTooltip('播放语音'), findsOneWidget);

    await tester.tap(find.text('第一行转录内容，第二行转录内容'));
    await tester.pump();
    expect(find.text('第一行转录内容，第二行转录内容'), findsOneWidget);
  });

  testWidgets('voice player screenshot', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('语音消息')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: VoiceMessagePlayer(
            fileId: 'voice-1',
            durationMs: 12500,
            transcript: '这是语音转录内容，可点击展开',
            resolveUrl: _unusedResolver,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('evidence/voice_message_player.png'),
    );
  });
}

Future<Uri?> _unusedResolver(String _) async => null;
