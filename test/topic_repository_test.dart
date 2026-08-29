import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('话题模型解析 metadata、详情来源消息和分页游标', () {
    final conversation = ChatConversation.fromJson(_conversationJson());
    expect(conversation.type, 'topic');
    expect(conversation.canSend, isFalse);
    expect(conversation.preview, '讨论发布计划');
    expect(conversation.topic!.parentConversationName, '产品群');
    expect(conversation.topic!.sourceSender.id, 'user-1');

    final detail = TopicDetail.fromJson(_detailJson());
    expect(detail.canArchive, isTrue);
    expect(detail.parentConversation.type, 'group');
    expect(detail.sourceMessage.body['content'], '讨论发布计划');
    expect(detail.sourceMessage.sender.avatar, '/avatars/alice.webp');

    final messageTopic = MessageTopic.fromJson({
      'archived': false,
      'conversation_id': 'topic-1',
      'recent_replies': [
        {
          'created_at': '2026-07-20T04:01:00Z',
          'id': 'message-2',
          'sender': {'id': 'user-2', 'type': 'user'},
          'summary': '后续消息',
        },
      ],
    });
    expect(messageTopic.recentReplies.single.summary, '后续消息');
    expect(
        MessageTopic.fromJson(messageTopic.toJson()).conversationId, 'topic-1');

    final systemReply = TopicSourceMessage.fromJson({
      'id': 'message-2',
      'created_at': '2026-07-20T04:01:00Z',
      'seq': 9,
      'summary': '后续消息',
      'sender': {'id': 'user-1', 'type': 'user'},
      'body': {'type': 'text', 'content': '后续消息'},
      'reply_to': {
        'id': 'system-message',
        'seq': 8,
        'summary': '系统通知',
        'sender': {'type': 'system', 'name': '系统'},
      },
    });
    expect(systemReply.replyTo?.sender.type, 'system');

    final page = TopicPage.fromJson({
      'topics': [_conversationJson()],
      'next_cursor': '  cursor-2  ',
    });
    expect(page.topics.single.id, 'topic-1');
    expect(page.nextCursor, 'cursor-2');
    expect(page.toJson()['next_cursor'], 'cursor-2');
  });

  test('HTTP 话题仓库对齐创建、列表、详情、参与和关闭路由', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'GET' &&
            path.endsWith('/topics') &&
            !path.contains('/conversations/topics/')) {
          return _jsonResponse({
            'data': {
              'next_cursor': 'cursor-2',
              'topics': [_conversationJson()]
            }
          });
        }
        if (request.method == 'GET' &&
            path == '/api/client/conversations/topics/topic-1') {
          return _jsonResponse({'data': _detailJson()});
        }
        if (request.method == 'POST' && path.endsWith('/topic')) {
          return _jsonResponse({
            'data': {'conversation': _conversationJson(), 'created': true}
          }, statusCode: 201);
        }
        if (request.method == 'POST' &&
            (path.endsWith('/participate') || path.endsWith('/archive'))) {
          return _jsonResponse({
            'data': {'conversation': _conversationJson()}
          });
        }
        return _jsonResponse({'data': _detailJson()});
      }),
    );

    final created = await repository.createTopic('parent-1', 'message-1');
    final page = await repository.topics('parent/1',
        cursor: 'cursor-1', limit: 20, status: 'archived');
    final detail = await repository.topicDetail('topic-1');
    final participated = await repository.participateTopic('topic-1');
    final archived = await repository.archiveTopic('topic-1');

    expect(created.id, 'topic-1');
    expect(page.nextCursor, 'cursor-2');
    expect(detail.sourceMessage.summary, '讨论发布计划');
    expect(participated.type, 'topic');
    expect(archived.topic!.archived, isFalse);
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /api/client/conversations/parent-1/messages/message-1/topic',
      'GET /api/client/conversations/parent%2F1/topics',
      'GET /api/client/conversations/topics/topic-1',
      'POST /api/client/conversations/topics/topic-1/participate',
      'POST /api/client/conversations/topics/topic-1/archive',
    ]);
    expect(requests[1].url.queryParameters, {
      'cursor': 'cursor-1',
      'limit': '20',
      'status': 'archived',
    });
    expect(
        requests.every((request) =>
            request.headers['authorization'] == 'Bearer test-token'),
        isTrue);
  });

  test('HTTP 话题详情缺少 reply_to 时回退父会话消息', () async {
    final requests = <http.BaseRequest>[];
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'test-token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/messages')) {
          return _jsonResponse({
            'data': {
              'messages': [
                {
                  'id': 'message-1',
                  'reply_to': {
                    'id': 'quoted-message',
                    'seq': 7,
                    'summary': '旧服务端的引用消息',
                    'sender': {
                      'id': 'user-2',
                      'name': 'Bob',
                      'type': 'user',
                    },
                  },
                },
              ],
            },
          });
        }
        return _jsonResponse({'data': _detailJson(includeReply: false)});
      }),
    );

    final detail = await repository.topicDetail('topic-1');

    expect(detail.sourceMessage.replyTo?.id, 'quoted-message');
    expect(detail.sourceMessage.replyTo?.sequence, 7);
    expect(detail.sourceMessage.replyTo?.summary, '旧服务端的引用消息');
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /api/client/conversations/topics/topic-1',
      'GET /api/client/conversations/parent-1/messages',
    ]);
    expect(requests[1].url.queryParameters, {
      'before_seq': '9',
      'limit': '1',
    });
  });

  test('DemoRepository 维护话题参与和关闭状态', () async {
    final repository = DemoRepository();
    final topic = await repository.createTopic('parent-1', 'message-1');
    expect((await repository.topics('parent-1')).topics.single.id, topic.id);
    expect((await repository.topicDetail(topic.id)).canParticipate, isFalse);
    final archived = await repository.archiveTopic(topic.id);
    expect(archived.topic!.archived, isTrue);
    expect((await repository.topics('parent-1', status: 'active')).topics,
        isEmpty);
  });
}

Map<String, dynamic> _conversationJson() => {
      'id': 'topic-1',
      'name': '讨论发布计划',
      'type': 'topic',
      'created_at': '2026-07-20T04:00:00Z',
      'avatar': '',
      'can_send': false,
      'last_message_summary': '讨论发布计划',
      'topic': {
        'archived': false,
        'parent_conversation_id': 'parent-1',
        'parent_conversation_name': '产品群',
        'parent_conversation_type': 'group',
        'participating': true,
        'source_message_id': 'message-1',
        'source_message_seq': 8,
        'source_sender': {
          'avatar': '/avatars/alice.webp',
          'id': 'user-1',
          'name': 'Alice',
          'type': 'user',
        },
      },
    };

Map<String, dynamic> _detailJson({bool includeReply = true}) => {
      'can_archive': true,
      'can_participate': false,
      'conversation': _conversationJson(),
      'parent_conversation': {
        'id': 'parent-1',
        'name': '产品群',
        'type': 'group',
      },
      'source_message': {
        'body': {'type': 'text', 'content': '讨论发布计划'},
        'created_at': '2026-07-20T04:00:00Z',
        'id': 'message-1',
        'revoked_at': null,
        'sender': {
          'avatar': '/avatars/alice.webp',
          'id': 'user-1',
          'name': 'Alice',
          'type': 'user',
        },
        'seq': 8,
        'summary': '讨论发布计划',
        if (includeReply)
          'reply_to': {
            'id': 'quoted-message',
            'seq': 7,
            'summary': '引用的消息',
            'sender': {
              'id': 'user-2',
              'name': 'Bob',
              'type': 'user',
            },
          },
      },
    };

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(jsonEncode(body), statusCode,
        headers: {'content-type': 'application/json'});
