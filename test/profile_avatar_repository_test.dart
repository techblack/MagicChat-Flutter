import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('系统头像通过 PATCH me 原样提交 builtin 路径', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((value) async {
        request = value;
        return _profileResponse('/assets/avatars/builtin/17.webp');
      }),
    );

    final user = await repository.updateProfile(
        avatar: '/assets/avatars/builtin/17.webp');

    expect(request.method, 'PATCH');
    expect(request.url.path, '/api/client/me');
    expect(request.headers['authorization'], 'Bearer test-token');
    expect(jsonDecode(request.body), {
      'avatar': '/assets/avatars/builtin/17.webp',
    });
    expect(user.avatar, '/assets/avatars/builtin/17.webp');
  });

  test('自定义头像通过 multipart POST me avatar 上传 WebP', () async {
    late http.BaseRequest request;
    late String body;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient.streaming((value, stream) async {
        request = value;
        body = utf8.decode(await stream.toBytes());
        final response =
            _profileBody('https://assets.example.com/users/user-1.webp');
        return http.StreamedResponse(
          http.ByteStream.fromBytes(utf8.encode(response)),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final user = await repository.uploadAvatar(AttachmentUpload(
      path: '',
      name: 'avatar.webp',
      mimeType: 'image/webp',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    ));

    expect(request.method, 'POST');
    expect(request.url.path, '/api/client/me/avatar');
    expect(request.headers['authorization'], 'Bearer test-token');
    expect(request.headers['content-type'], startsWith('multipart/form-data;'));
    expect(body, contains('name="file"'));
    expect(body, contains('filename="avatar.webp"'));
    expect(body, contains('content-type: image/webp'));
    expect(user.avatar, 'https://assets.example.com/users/user-1.webp');
  });
}

http.Response _profileResponse(String avatar) =>
    http.Response(_profileBody(avatar), 200,
        headers: {'content-type': 'application/json'});

String _profileBody(String avatar) => jsonEncode({
      'success': true,
      'data': {
        'user': {
          'id': 'user-1',
          'name': '演示用户',
          'email': 'demo@example.com',
          'avatar': avatar,
        },
      },
    });
