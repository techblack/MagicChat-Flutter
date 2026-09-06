import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';

void main() {
  test('2000 个用户资料按最多 4 个请求一波并发解析', () async {
    final userIds = List.generate(2000, (index) => 'user-$index');
    final requests = <http.Request>[];
    var active = 0;
    var maxActive = 0;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/client/contacts') {
          return http.Response(
              jsonEncode({
                'data': {
                  'apps': [],
                  'groups': [],
                  'user_ids': userIds,
                  'directory_mode': 'organization',
                }
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        active--;
        final ids =
            (jsonDecode(request.body)['user_ids'] as List).cast<String>();
        return http.Response(
            jsonEncode({
              'data': {
                'users': [
                  for (final id in ids) {'id': id, 'name': '成员 $id'}
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

    final directory = await repository.contactDirectory();

    expect(directory.contacts, hasLength(2000));
    expect(
        requests.where((request) => request.method == 'POST'), hasLength(20));
    expect(maxActive, lessThanOrEqualTo(4));
  });

  test('通讯录超过 100 个用户时按分块解析完整联系人列表', () async {
    final userIds = List.generate(205, (index) => 'user-$index');
    final requests = <http.Request>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/client/contacts') {
          return http.Response(
              jsonEncode({
                'data': {
                  'apps': [],
                  'groups': [],
                  'user_ids': userIds,
                  'directory_mode': 'organization',
                }
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final ids =
            (jsonDecode(request.body)['user_ids'] as List).cast<String>();
        return http.Response(
            jsonEncode({
              'data': {
                'users': [
                  for (final id in ids) {'id': id, 'name': '成员 $id'}
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

    final directory = await repository.contactDirectory();

    expect(directory.contacts, hasLength(205));
    expect(directory.contacts.last.id, 'user-204');
    expect(requests.where((request) => request.method == 'POST'), hasLength(3));
  });

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
              'apps': [
                {
                  'id': 'app-assistant',
                  'name': 'Assistant',
                  'type': 'app',
                  'description': 'Conversation helper',
                  'creator_user_id': 'user-creator',
                  'online': true,
                }
              ],
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
    final group =
        directory.contacts.where((item) => item.type == 'group').single;
    final app = directory.contacts.where((item) => item.type == 'app').single;
    expect(group.joined, isFalse);
    expect(group.memberCount, 3);
    expect(group.visibility, 'public');
    expect(app.description, 'Conversation helper');
    expect(app.creatorUserId, 'user-creator');
    expect(app.online, isTrue);
  });

  test('通讯录搜索会将关键词编码到查询参数', () async {
    Uri? requested;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
            jsonEncode({
              'data': {
                'apps': [],
                'groups': [],
                'user_ids': [],
                'directory_mode': 'organization',
              }
            }),
            200);
      }),
    );

    await repository.contactDirectory(keyword: 'alice@example.com');

    expect(
        requested,
        Uri.parse(
            'https://chat.example.com/api/client/contacts?keyword=alice%40example.com'));
  });
}
