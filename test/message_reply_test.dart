import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('文本消息按服务端契约携带 reply_to_message_id', () async {
    late http.Request request;
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'data': {}}), 201);
      }),
    );

    await repository.sendMessage('conversation-1', '回复内容',
        replyToMessageId: 'message-1',
        clientMessageId: '2667e1f1-3b23-4be5-9ec6-1b33a2b13e31');

    expect(jsonDecode(request.body), {
      'client_message_id': '2667e1f1-3b23-4be5-9ec6-1b33a2b13e31',
      'body': {'type': 'text', 'content': '回复内容'},
      'reply_to_message_id': 'message-1',
    });
  });

  test('历史消息解析 reply_to 摘要和发送者', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'messages': [
                {
                  'id': 'message-2',
                  'seq': 2,
                  'created_at': '2026-09-04T11:22:33Z',
                  'body': {'type': 'text', 'content': 'new content'},
                  'sender': {'id': 'user-2', 'name': 'Alice'},
                  'reply_to': {
                    'id': 'message-1',
                    'sender': {'id': 'user-1', 'type': 'user'},
                    'seq': 1,
                    'summary': 'original summary',
                  },
                  'topic': {
                    'archived': false,
                    'conversation_id': 'topic-1',
                    'recent_replies': [
                      {
                        'created_at': '2026-07-20T04:02:00Z',
                        'id': 'message-3',
                        'sender': {'id': 'user-3', 'type': 'user'},
                        'summary': 'topic reply',
                      }
                    ],
                  },
                }
              ]
            }
          }),
          200)),
    );

    final message = (await repository.messages('conversation-1')).single;
    expect(message.replyTo?.id, 'message-1');
    expect(message.createdAt, '2026-09-04T11:22:33Z');
    expect(message.replyTo?.author, '用户');
    expect(message.replyTo?.text, 'original summary');
    expect(message.replyTo?.sequence, 1);
    expect(message.topic?.conversationId, 'topic-1');
    expect(message.topic?.recentReplies.single.summary, 'topic reply');
  });

  test('仅返回引用消息 ID 时保留引用关系并隐藏原始 ID', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'messages': [
                {
                  'id': 'message-2',
                  'seq': 2,
                  'body': {'type': 'text', 'content': 'new content'},
                  'sender': {'id': 'user-2'},
                  'reply_to_message_id': 'message-1',
                }
              ]
            }
          }),
          200)),
    );

    final message = (await repository.messages('conversation-1')).single;
    expect(message.replyTo?.id, 'message-1');
    expect(message.replyTo?.text, '[消息]');
    expect(message.author, '成员');
  });

  test('引用摘要为消息 ID 时优先读取嵌套正文和联系人资料', () {
    final reply = MessageReply.fromJson({
      'id': 'message-1',
      'summary': 'message-1',
      'sender': {'id': 'user-1', 'nickname': '小爱'},
      'seq': 1,
      'message': {
        'body': {'type': 'text', 'content': '原消息正文'},
      },
    });

    expect(reply.id, 'message-1');
    expect(reply.author, '小爱');
    expect(reply.authorId, 'user-1');
    expect(reply.sequence, 1);
    expect(reply.text, '原消息正文');
  });

  test('引用复杂消息时使用消息类型摘要而不是原始消息 ID', () {
    final reply = MessageReply.fromJson({
      'id': 'message-1',
      'summary': 'message-1',
      'message': {
        'body': {'type': 'file', 'name': '设计稿.pdf'},
      },
    });

    expect(reply.text, '[文件] 设计稿.pdf');
    expect(reply.text, isNot(contains('message-1')));
  });

  test('历史撤回消息使用撤回占位，不读取缺失正文', () async {
    final repository = HttpMagicChatRepository(
      serverUrl: 'https://chat.example.com',
      sessionToken: 'token',
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'messages': [
                {
                  'id': 'revoked-1',
                  'seq': 3,
                  'sender': {'id': 'user-2', 'name': 'Alice'},
                  'revoked_at': '2026-08-29T12:00:00Z',
                  'editable_body': {
                    'type': 'markdown',
                    'content': '# Revoked body'
                  },
                }
              ]
            }
          }),
          200)),
    );

    final message = (await repository.messages('conversation-1')).single;
    expect(message.contentType, 'revoked');
    expect(message.text, '消息已撤回');
    expect(message.editableText, '# Revoked body');
    expect(message.editableContentType, 'markdown');
  });
}
