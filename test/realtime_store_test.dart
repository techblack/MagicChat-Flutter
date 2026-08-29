import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('按 cursor 忽略重复事件并投影消息', () {
    final store = RealtimeStore();
    store.apply({
      'event': 'message.created',
      'cursor': 2,
      'payload': {
        'id': 'm1',
        'body': {'type': 'text', 'content': '你好'}
      }
    });
    store.apply({
      'event': 'message.created',
      'cursor': 1,
      'payload': {
        'id': 'm2',
        'body': {'type': 'text', 'content': '旧事件'}
      }
    });
    expect(store.cursor, 2);
    expect(store.messages['m1']?.text, '你好');
    expect(store.messages.containsKey('m2'), isFalse);
  });

  test('投影会话置顶和免打扰事件', () {
    final store = RealtimeStore();
    store.conversations['c1'] = const ChatConversation(id: 'c1', title: '会话');
    store.apply({
      'event': 'conversation.pin_updated',
      'cursor': 1,
      'payload': {'conversation_id': 'c1', 'pinned': true}
    });
    expect(store.conversations['c1']?.pinned, isTrue);
    store.apply({
      'event': 'conversation.mute_updated',
      'cursor': 2,
      'payload': {'conversation_id': 'c1', 'muted': true}
    });
    expect(store.conversations['c1']?.muted, isTrue);
  });

  test('投影用户在线状态事件', () {
    final store = RealtimeStore();
    store.contacts['u1'] = const Contact(
        id: 'u1',
        name: 'Alice',
        online: false,
        nickname: '小爱',
        email: 'alice@example.com',
        avatar: '/avatar.webp');
    store.apply({
      'event': 'user.presence.updated',
      'cursor': 1,
      'payload': {'user_id': 'u1', 'online': true}
    });
    expect(store.contacts['u1']?.online, isTrue);
    expect(store.contacts['u1']?.nickname, '小爱');
    expect(store.contacts['u1']?.email, 'alice@example.com');
    expect(store.contacts['u1']?.avatar, '/avatar.webp');
  });

  test('按当前用户 ID 标记实时消息归属', () {
    final store = RealtimeStore()..setCurrentUserId('me');
    store.apply({
      'event': 'message.created',
      'cursor': 1,
      'payload': {
        'id': 'm1',
        'sender': {'id': 'me', 'name': '我'},
        'body': {'type': 'text', 'content': '自己的消息'}
      }
    });
    expect(store.messages['m1']?.mine, isTrue);
  });

  test('实时回应更新替换消息回应列表', () {
    final store = RealtimeStore()..setCurrentUserId('me');
    store.messages['m1'] =
        const ChatMessage(id: 'm1', author: 'Alice', text: 'hi');
    store.apply({
      'event': 'message.reactions_updated',
      'cursor': 1,
      'payload': {
        'message_id': 'm1',
        'actor_user_id': 'me',
        'actor_text': '👍',
        'actor_reacted': true,
        'reactions': [
          {'text': '👍', 'count': 1}
        ]
      }
    });
    expect(store.messages['m1']?.reactions.single.reactedByMe, isTrue);
  });

  test('实时回应更新保留表情参与者', () {
    final store = RealtimeStore();
    store.messages['m1'] =
        const ChatMessage(id: 'm1', author: 'Alice', text: 'hi');
    store.apply({
      'event': 'message.reactions_updated',
      'cursor': 1,
      'payload': {
        'message_id': 'm1',
        'reactions': [
          {
            'text': '👍',
            'count': 2,
            'users': [
              {'id': 'u1', 'name': 'Alice'},
              {'id': 'u2'},
              {'id': 4, 'name': 'invalid'},
            ],
          }
        ],
      }
    });
    final reaction = store.messages['m1']!.reactions.single;
    expect(reaction.count, 2);
    expect(reaction.users.map((user) => user.id), ['u1', 'u2']);
    expect(reaction.users.last.name, isEmpty);
  });

  test('撤回消息忽略迟到的回应更新', () {
    final store = RealtimeStore();
    store.messages['m1'] = const ChatMessage(
        id: 'm1', contentType: 'revoked', text: '消息已撤回', author: 'Alice');
    store.apply({
      'event': 'message.reactions_updated',
      'cursor': 1,
      'payload': {
        'message_id': 'm1',
        'reactions': [
          {'text': '👍', 'count': 1}
        ]
      }
    });
    expect(store.messages['m1']?.reactions, isEmpty);
  });

  test('兼容服务端 message envelope 包装', () {
    final store = RealtimeStore();
    store.apply({
      'event': 'message.created',
      'cursor': 1,
      'payload': {
        'message': {
          'id': 'm2',
          'sender': {'id': 'u2', 'name': 'Bob'},
          'body': {'type': 'text', 'content': 'envelope'}
        }
      }
    });
    expect(store.messages['m2']?.text, 'envelope');
  });

  test('实时撤回事件不把缺失正文渲染成 null', () {
    final store = RealtimeStore();
    store.apply({
      'event': 'message.updated',
      'cursor': 1,
      'payload': {
        'id': 'revoked-1',
        'conversation_id': 'c1',
        'revoked_at': '2026-08-29T12:00:00Z',
      }
    });
    expect(store.messages['revoked-1']?.contentType, 'revoked');
    expect(store.messages['revoked-1']?.text, '消息已撤回');
  });

  test('撤回更新保留已有消息的发送者和会话归属', () {
    final store = RealtimeStore()..setCurrentUserId('me');
    store.apply({
      'event': 'message.created',
      'cursor': 1,
      'payload': {
        'id': 'm1',
        'conversation_id': 'c1',
        'seq': 4,
        'sender': {'id': 'alice', 'name': 'Alice'},
        'body': {'type': 'text', 'content': '原文'},
        'reactions': [
          {'text': '👍', 'count': 1}
        ],
        'reply_to': {
          'id': 'm0',
          'sender': {'id': 'me'},
          'summary': '上一条消息'
        }
      }
    });
    store.apply({
      'event': 'message.updated',
      'cursor': 2,
      'payload': {
        'message': {
          'id': 'm1',
          'revoked_at': '2026-08-29T12:00:00Z',
          'sender': {'id': 'alice', 'type': 'user'},
          'seq': 4,
          'conversation_id': 'c1'
        }
      }
    });
    final message = store.messages['m1'];
    expect(message?.author, 'Alice');
    expect(message?.conversationId, 'c1');
    expect(message?.replyTo, isNull);
    expect(message?.contentType, 'revoked');
    expect(message?.reactions, isEmpty);
  });

  test('投影消息话题摘要并在回应更新时保留话题', () {
    final store = RealtimeStore();
    store.apply({
      'event': 'message.created',
      'cursor': 1,
      'payload': {
        'id': 'source-1',
        'conversation_id': 'parent-1',
        'sender': {'id': 'u1', 'type': 'user', 'name': 'Alice'},
        'body': {'type': 'text', 'content': '来源消息'},
        'topic': {
          'archived': false,
          'conversation_id': 'topic-1',
          'recent_replies': [
            {
              'created_at': '2026-07-20T04:01:00Z',
              'id': 'reply-1',
              'sender': {'id': 'u2', 'type': 'user'},
              'summary': '话题回复',
            }
          ],
        },
      }
    });
    expect(store.messages['source-1']?.topic?.conversationId, 'topic-1');
    store.apply({
      'event': 'message.reactions_updated',
      'cursor': 2,
      'payload': {
        'message_id': 'source-1',
        'reactions': [
          {'text': '👍', 'count': 1}
        ],
      }
    });
    expect(
        store.messages['source-1']?.topic?.recentReplies.single.id, 'reply-1');
  });

  test('投影话题参与和关闭事件并保持来源元数据', () {
    final store = RealtimeStore();
    store.conversations['topic-1'] = ChatConversation(
        id: 'topic-1',
        title: '话题',
        type: 'topic',
        topic: const TopicMetadata(
            archived: false,
            parentConversationId: 'parent-1',
            parentConversationName: '群聊',
            parentConversationType: 'group',
            participating: false,
            sourceMessageId: 'message-1',
            sourceMessageSeq: 8,
            sourceSender: TopicSourceSender(id: 'user-1', type: 'user')));
    store.apply({
      'event': 'topic.participated',
      'cursor': 1,
      'payload': {
        'conversation_id': 'topic-1',
        'parent_conversation_id': 'parent-1',
        'source_message_id': 'message-1',
      }
    });
    expect(store.conversations['topic-1']?.topic?.participating, isTrue);
    store.apply({
      'event': 'topic.archived',
      'cursor': 2,
      'payload': {
        'conversation_id': 'topic-1',
        'parent_conversation_id': 'parent-1',
        'source_message_id': 'message-1',
        'archived': true,
      }
    });
    expect(store.conversations['topic-1']?.topic?.archived, isTrue);
    expect(store.conversations['topic-1']?.canSend, isFalse);
  });

  test('话题创建事件不把未参与者错误标为已参与', () {
    final store = RealtimeStore();
    store.conversations['topic-1'] = ChatConversation(
        id: 'topic-1',
        title: '话题',
        type: 'topic',
        topic: const TopicMetadata(
            archived: false,
            parentConversationId: 'parent-1',
            parentConversationName: '群聊',
            parentConversationType: 'group',
            participating: false,
            sourceMessageId: 'message-1',
            sourceMessageSeq: 8,
            sourceSender: TopicSourceSender(id: 'user-1', type: 'user')));
    store.apply({
      'event': 'topic.created',
      'payload': {
        'conversation_id': 'topic-1',
        'parent_conversation_id': 'parent-1',
        'source_message_id': 'message-1',
      }
    });
    expect(store.conversations['topic-1']?.topic?.participating, isFalse);
  });
}
