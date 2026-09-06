import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('HTTP 仓库在上传和下载期间报告活跃文件传输', () async {
    final client = _PendingClient();
    final repository = HttpMagicChatRepository(
        serverUrl: 'https://chat.example.com',
        sessionToken: 'token',
        client: client);

    final download =
        repository.downloadResource(Uri.parse('https://chat.example.com/a'));
    await client.requested.future;
    expect(repository.hasActiveTransfers, isTrue);
    client.complete(http.StreamedResponse(Stream.value([1, 2, 3]), 200));
    expect(await download, Uint8List.fromList([1, 2, 3]));
    expect(repository.hasActiveTransfers, isFalse);

    client.reset();
    final upload = repository.uploadTemporaryFile(AttachmentUpload(
        path: '',
        name: 'image.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1])));
    await client.requested.future;
    expect(repository.hasActiveTransfers, isTrue);
    client.complete(http.StreamedResponse(
        Stream.value(
            utf8.encode('{"data":{"file":{"id":"file-1","size_bytes":1}}}')),
        201));
    expect((await upload).id, 'file-1');
    expect(repository.hasActiveTransfers, isFalse);
  });
}

class _PendingClient extends http.BaseClient {
  Completer<void> requested = Completer<void>();
  Completer<http.StreamedResponse> response =
      Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requested.complete();
    return response.future;
  }

  void complete(http.StreamedResponse value) => response.complete(value);

  void reset() {
    requested = Completer<void>();
    response = Completer<http.StreamedResponse>();
  }
}
