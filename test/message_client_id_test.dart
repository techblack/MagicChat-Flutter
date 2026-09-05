import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('图片、文件和语音重试复用显式客户端消息 ID', () async {
    final bodies = <String>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient.streaming((_, body) async {
        bodies.add(utf8.decode(await body.toBytes()));
        return http.StreamedResponse(http.ByteStream.fromBytes(const []), 200);
      }),
    );
    final upload = AttachmentUpload(
      path: '',
      name: 'sample.bin',
      mimeType: 'application/octet-stream',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    const ids = [
      '2667e1f1-3b23-4be5-9ec6-1b33a2b13e31',
      'd92a0161-390f-43f3-8fd3-15ccac248614',
      '53dd1f72-94f5-47be-9fa8-8b2b3a2f85df',
    ];
    for (var attempt = 0; attempt < 2; attempt++) {
      await repository.sendImage('conversation-1', upload,
          clientMessageId: ids[0]);
      await repository.sendFile('conversation-1', upload,
          clientMessageId: ids[1]);
      await repository.sendVoice('conversation-1', upload,
          durationMs: 1200, clientMessageId: ids[2]);
    }

    expect(bodies, hasLength(6));
    for (var index = 0; index < bodies.length; index++) {
      final body = bodies[index];
      final expectedId = ids[index % ids.length];
      expect(body, contains('name="client_message_id"'));
      expect(body, contains('\r\n\r\n$expectedId\r\n'));
    }
  });
}
