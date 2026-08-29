import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('调用删除好友 API', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode({
              'data': {'user_id': 'user/1'}
            }),
            200);
      }),
    );

    await repository.deleteFriend('user/1');

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'DELETE /api/client/friends/user%2F1',
    ]);
    expect(requests.single.headers['authorization'], 'Bearer test-token');
  });

  test('精确查找用户后批量解析资料', () async {
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/client/users/search') {
          expect(jsonDecode(request.body), {'query': 'alice@example.com'});
          return http.Response(
              jsonEncode({
                'data': {
                  'user_ids': ['user-alice']
                }
              }),
              200);
        }
        expect(request.url.path, '/api/client/users/resolve');
        expect(jsonDecode(request.body), {
          'user_ids': ['user-alice']
        });
        return http.Response(
            jsonEncode({
              'data': {
                'users': [
                  {
                    'id': 'user-alice',
                    'name': 'Alice',
                    'email': 'alice@example.com',
                    'online': true,
                  }
                ]
              }
            }),
            200);
      }),
    );

    final users = await repository.searchUsers(' alice@example.com ');

    expect(users.single.id, 'user-alice');
    expect(users.single.name, 'Alice');
    expect(users.single.email, 'alice@example.com');
    expect(users.single.online, isTrue);
    expect(requests, hasLength(2));
    expect(
        requests.every((request) =>
            request.headers['Authorization'] == 'Bearer test-token'),
        isTrue);
  });

  test('保留服务端返回的通讯录模式', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async => http.Response(
          jsonEncode({
            'data': {
              'apps': [],
              'groups': [
                {
                  'id': 'group-public',
                  'name': 'public-group',
                  'type': 'group',
                  'joined': false,
                  'member_count': 3,
                  'visibility': 'public',
                }
              ],
              'user_ids': [],
              'directory_mode': 'friends',
            }
          }),
          200)),
    );

    final directory = await repository.contactDirectory();

    expect(directory.mode, 'friends');
    expect(directory.supportsFriendManagement, isTrue);
    expect(directory.contacts.single, isA<Contact>());
    expect(directory.contacts.single.joined, isFalse);
    expect(directory.contacts.single.memberCount, 3);
    expect(directory.contacts.single.visibility, 'public');
  });
}
