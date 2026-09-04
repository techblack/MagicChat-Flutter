import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('HTTP 消息检索传递会话、发送人和 UTC 时间范围', () async {
    late Uri requestUri;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((request) async {
        requestUri = request.url;
        return _jsonResponse({
          'data': {'items': <Object>[]}
        });
      }),
    );

    await repository.searchMessages(
      ' 发布计划 ',
      conversationId: 'conversation-1',
      senderId: 'user-2',
      from: DateTime.parse('2026-07-01T08:00:00+08:00'),
      to: DateTime.parse('2026-08-01T18:30:00+08:00'),
    );

    expect(requestUri.path, '/api/client/search/messages');
    expect(requestUri.queryParameters, {
      'keyword': '发布计划',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-2',
      'from': '2026-07-01T00:00:00.000Z',
      'to': '2026-08-01T10:30:00.000Z',
    });
  });

  test('HTTP 仓库保留服务端错误并通知会话失效', () async {
    var unauthorizedCount = 0;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'expired-token',
      onUnauthorized: () => unauthorizedCount++,
      client: MockClient((_) async => _jsonResponse({
            'success': false,
            'error': {'code': 'unauthorized', 'message': '会话已失效'},
          }, statusCode: 401)),
    );

    await expectLater(
      repository.currentUser(),
      throwsA(isA<MagicChatRequestException>()
          .having((error) => error.statusCode, 'statusCode', 401)
          .having((error) => error.code, 'code', 'unauthorized')
          .having((error) => error.message, 'message', '会话已失效')),
    );
    expect(unauthorizedCount, 1);
  });

  test('multipart 接口也解析业务错误 envelope', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((_) async => _jsonResponse({
            'success': false,
            'error': {'code': 'avatar_invalid', 'message': '头像尺寸不正确'},
          }, statusCode: 422)),
    );

    await expectLater(
      repository.uploadAppAvatar(
          'app-1',
          AttachmentUpload(
              path: '',
              name: 'avatar.webp',
              mimeType: 'image/webp',
              bytes: Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<MagicChatRequestException>()
          .having((error) => error.statusCode, 'statusCode', 422)
          .having((error) => error.code, 'code', 'avatar_invalid')
          .having((error) => error.message, 'message', '头像尺寸不正确')),
    );
  });

  test('HTTP 消息解析选择状态及选项统计', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((request) async {
        expect(request.url.path,
            '/api/client/conversations/conversation-1/messages');
        return _jsonResponse({
          'data': {
            'messages': [
              {
                'id': 'choice-1',
                'body': {
                  'type': 'choice',
                  'content_type': 'text',
                  'content': '请选择',
                  'selection': 'multiple',
                  'options': [
                    {'id': 'a', 'label': '选项 A'},
                    {'id': 'b', 'label': '选项 B'},
                  ],
                },
                'sender': {'id': 'user-1', 'name': 'Alice'},
                'choice': {
                  'my_option_ids': ['b'],
                  'response_count': 3,
                  'options': [
                    {'id': 'a', 'response_count': 1},
                    {'id': 'b', 'response_count': 3},
                  ],
                },
              }
            ]
          }
        });
      }),
    );
    final message = (await repository.messages('conversation-1')).single;
    expect(message.choice?.myOptionIds, ['b']);
    expect(message.choice?.responseCount, 3);
    expect(message.choice?.options.first.responseCount, 1);
  });

  test('HTTP 仓库按表情文本查询参与者并解析用户列表', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com/base',
      sessionToken: 'test-token',
      client: MockClient((value) async {
        request = value;
        return _jsonResponse({
          'data': {
            'conversation_id': 'conversation/1',
            'message_id': 'message/1',
            'text': '👍 &',
            'users': [
              {'id': 'u1', 'name': 'Alice'},
              {'id': 'u2'},
            ],
          }
        });
      }),
    );

    final users = await repository
        .listReactionUsers('conversation/1', 'message/1', text: '👍 &');
    expect(request.method, 'GET');
    expect(request.url.path,
        '/base/api/client/conversations/conversation%2F1/messages/message%2F1/reactions/users');
    expect(request.url.queryParameters['text'], '👍 &');
    expect(request.headers['authorization'], 'Bearer test-token');
    expect(users.map((user) => user.id), ['u1', 'u2']);
    expect(users.last.name, isEmpty);
  });

  test('HTTP 仓库拒绝不匹配的表情参与者响应', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((_) async => _jsonResponse({
            'data': {
              'conversation_id': 'wrong',
              'message_id': 'message-1',
              'text': '👍',
              'users': [],
            }
          })),
    );

    await expectLater(
        repository.listReactionUsers('conversation-1', 'message-1', text: '👍'),
        throwsA(isA<FormatException>()));
  });

  test('OwnedApp 和 AppCredentials 使用服务端 snake_case 字段往返', () {
    final app = OwnedApp.fromJson(_appJson());
    expect(app.id, 'app-1');
    expect(app.connectionStatus, 'online');
    expect(app.visibility, 'restricted');
    expect(app.userIds, ['user-2']);
    expect(app.toJson(), _appJson());

    final credentials = AppCredentials.fromJson({
      'app': _appJson(),
      'connection_secret': 'secret-1',
    });
    expect(credentials.app.id, 'app-1');
    expect(credentials.connectionSecret, 'secret-1');
    expect(credentials.toJson()['connection_secret'], 'secret-1');
  });

  test('HTTP 应用仓库覆盖管理序列并按可见范围发送授权用户', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'GET' && path == '/api/client/apps') {
          return _jsonResponse({
            'data': {
              'apps': [_appJson()]
            }
          });
        }
        if (request.method == 'POST' && path == '/api/client/apps') {
          return _jsonResponse({
            'data': {
              'app': _appJson(),
              'connection_secret': 'created-secret',
            }
          }, statusCode: 201);
        }
        if (request.method == 'GET' &&
            (path == '/api/client/apps/app/1' ||
                path == '/api/client/apps/app%2F1')) {
          return _jsonResponse({
            'data': {'app': _appJson(), 'connection_secret': 'current-secret'}
          });
        }
        if (request.method == 'PATCH' && path == '/api/client/apps/app-1') {
          return _jsonResponse({
            'data': {'app': _appJson()}
          });
        }
        if (request.method == 'POST' &&
            (path.endsWith('/enable') || path.endsWith('/disable'))) {
          return _jsonResponse({
            'data': {'app': _appJson()}
          });
        }
        if (request.method == 'POST' && path.endsWith('/secret/regenerate')) {
          return _jsonResponse({
            'data': {'app': _appJson(), 'connection_secret': 'new-secret'}
          });
        }
        if (request.method == 'DELETE') {
          return _jsonResponse({'data': {}});
        }
        if (request.method == 'POST' && path.endsWith('/avatar')) {
          return _jsonResponse({
            'data': {'app': _appJson()}
          });
        }
        return _jsonResponse({
          'data': {'app': _appJson()}
        });
      }),
    );

    expect((await repository.apps()).single.id, 'app-1');
    final created = await repository.createApp('新应用',
        description: '说明', visibility: 'public', userIds: ['must-not-send']);
    expect(created.connectionSecret, 'created-secret');
    final createRequest = requests.firstWhere((request) =>
        request.method == 'POST' && request.url.path == '/api/client/apps');
    expect(jsonDecode((createRequest as http.Request).body), {
      'name': '新应用',
      'description': '说明',
      'visibility': 'public',
      'user_ids': [],
    });

    final credentials = await repository.getAppCredentials('app/1');
    expect(credentials.connectionSecret, 'current-secret');
    final updated = await repository
        .updateApp('app-1', visibility: 'public', userIds: ['must-not-send']);
    expect(updated.id, 'app-1');
    final updateRequest = requests
        .firstWhere((request) => request.method == 'PATCH') as http.Request;
    expect(jsonDecode(updateRequest.body)['user_ids'], isEmpty);

    expect((await repository.setAppEnabled('app-1', false)).id, 'app-1');
    expect((await repository.regenerateAppSecret('app-1')).connectionSecret,
        'new-secret');
    await repository.deleteApp('app-1');
    final avatar = await repository.uploadAppAvatar(
        'app-1',
        AttachmentUpload(
            path: '',
            name: 'avatar.webp',
            mimeType: 'image/webp',
            bytes: Uint8List.fromList([1, 2, 3])));
    expect(avatar.id, 'app-1');
    expect(
        requests.any((request) =>
            request.method == 'POST' &&
            request.url.path == '/api/client/apps/app-1/avatar'),
        isTrue);
    expect(
        requests.every((request) =>
            request.headers['authorization'] == 'Bearer test-token'),
        isTrue);
  });

  test('DemoRepository 可创建、更新、重置和删除应用', () async {
    final repository = DemoRepository();
    final created = await repository
        .createApp('受限应用', visibility: 'restricted', userIds: ['user-2']);
    expect((await repository.apps()).any((item) => item.id == created.app.id),
        isTrue);
    expect(
        (await repository.getAppCredentials(created.app.id)).connectionSecret,
        created.connectionSecret);
    expect(
        (await repository.updateApp(created.app.id,
                visibility: 'public', userIds: ['user-2']))
            .userIds,
        isEmpty);
    expect((await repository.setAppEnabled(created.app.id, false)).enabled,
        isFalse);
    final regenerated = await repository.regenerateAppSecret(created.app.id);
    expect(regenerated.connectionSecret, isNot(created.connectionSecret));
    await repository.deleteApp(created.app.id);
    expect((await repository.apps()).any((item) => item.id == created.app.id),
        isFalse);
  });
}

Map<String, dynamic> _appJson() => {
      'avatar': '/assets/apps/app-1.webp',
      'connection_status': 'online',
      'created_at': '2026-08-29T10:00:00Z',
      'description': '报表机器人',
      'enabled': true,
      'id': 'app-1',
      'name': '报表应用',
      'updated_at': '2026-08-29T11:00:00Z',
      'user_ids': ['user-2'],
      'visibility': 'restricted',
    };

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(jsonEncode(body), statusCode,
        headers: {'content-type': 'application/json'});
