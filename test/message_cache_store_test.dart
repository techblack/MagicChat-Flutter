import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const alice = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-alice');
  const bob = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-bob');
  const otherServer = MessageCacheScope(
      serverUrl: 'https://other.example.com', userId: 'user-alice');

  late Directory directory;
  late MessageCacheStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('magicchat-message-db-');
    store = MessageCacheStore(databaseDirectory: directory.path);
  });

  tearDown(() async {
    await store.clearAll();
    await store.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('Native 数据库启用 WAL 并按会话类型分片', () async {
    await store.write(alice, 'same-conversation', [
      _message('direct-message', 1, '私聊消息'),
    ]);
    await store.write(
        alice,
        'same-conversation',
        [
          _message('group-message', 1, '群聊消息'),
        ],
        conversationType: 'group');

    expect(await store.journalMode(alice), 'wal');
    expect(await store.journalMode(alice, conversationType: 'group'), 'wal');
    expect(await store.databasePath(alice),
        isNot(await store.databasePath(alice, conversationType: 'group')));
    expect((await store.read(alice, 'same-conversation')).single['id'],
        'direct-message');
    expect(
        (await store.read(alice, 'same-conversation',
                conversationType: 'group'))
            .single['id'],
        'group-message');
  });

  test('同一会话按账号和服务器隔离并按序号稳定排序', () async {
    await store.write(alice, 'conversation-1', [
      _message('alice-3', 3, '第三条'),
      _message('alice-1', 1, '第一条'),
      _message('alice-2', 2, '第二条'),
    ]);
    await store.write(bob, 'conversation-1', [
      _message('bob-message', 1, 'Bob'),
    ]);

    expect(
        (await store.read(alice, 'conversation-1'))
            .map((message) => message['id']),
        ['alice-1', 'alice-2', 'alice-3']);
    expect(
        (await store.read(bob, 'conversation-1')).single['id'], 'bob-message');
    expect(await store.read(otherServer, 'conversation-1'), isEmpty);
    expect(
        (await store.read(alice, 'conversation-1', beforeSequence: 3, limit: 1))
            .single['id'],
        'alice-2');
  });

  test('增量 upsert 新增消息并以 ID 原位更新', () async {
    await store.write(alice, 'conversation-1', [
      _message('message-1', 1, '旧内容'),
      _message('message-2', 2, '第二条'),
    ]);
    await store.upsert(
        alice, 'conversation-1', _message('message-1', 1, '新内容'));
    await store.upsertAll(alice, 'conversation-1', [
      _message('message-3', 3, '第三条'),
      _message('message-4', 4, '第四条'),
    ]);

    final messages = await store.read(alice, 'conversation-1');
    expect(messages.map((message) => message['id']),
        ['message-1', 'message-2', 'message-3', 'message-4']);
    expect(messages.first['text'], '新内容');
  });

  test('本地搜索组合关键词、发送人、时间和类型过滤', () async {
    await store.write(alice, 'conversation-1', [
      _message('old', 1, '旧版 release',
          author: 'Alice',
          authorId: 'alice',
          createdAt: '2026-08-01T10:00:00Z'),
      _message('match', 2, 'Release Ready',
          author: 'Alice',
          authorId: 'alice',
          createdAt: '2026-09-04T10:00:00Z'),
      _message('wrong-sender', 3, 'Release Ready',
          author: 'Bob', authorId: 'bob', createdAt: '2026-09-04T11:00:00Z'),
      _message('wrong-type', 4, 'Release 图',
          author: 'Alice',
          authorId: 'alice',
          contentType: 'image',
          createdAt: '2026-09-04T12:00:00Z'),
    ]);

    final results = await store.search(alice, 'conversation-1',
        keyword: 'release',
        senderId: 'alice',
        from: DateTime.parse('2026-09-01T00:00:00Z'),
        to: DateTime.parse('2026-09-05T00:00:00Z'),
        contentTypes: const ['text']);

    expect(results.map((message) => message['id']), ['match']);
  });

  test('可分别清理会话、账号作用域和全部缓存', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('magicchat.messages.legacy', '[]');
    await preferences.setString('magicchat.document.draft', 'draft');
    await store.write(alice, 'direct-1', [_message('alice-direct', 1, 'A')]);
    await store.write(alice, 'group-1', [_message('alice-group', 1, 'B')],
        conversationType: 'group');
    await store.write(bob, 'direct-1', [_message('bob-direct', 1, 'C')]);

    await store.clear(alice, 'direct-1');
    expect(await store.read(alice, 'direct-1'), isEmpty);
    expect(await store.read(alice, 'group-1', conversationType: 'group'),
        isNotEmpty);

    await store.clearScope(alice);
    expect(
        await store.read(alice, 'group-1', conversationType: 'group'), isEmpty);
    expect(await store.read(bob, 'direct-1'), isNotEmpty);

    await store.clearAll();
    expect(await store.read(bob, 'direct-1'), isEmpty);
    expect(preferences.containsKey('magicchat.messages.legacy'), isFalse);
    expect(preferences.getString('magicchat.document.draft'), 'draft');
  });

  test('损坏的旧 JSON 自动丢弃且不阻塞 SQLite 读取', () async {
    final preferences = await SharedPreferences.getInstance();
    final cacheKey = store.key(alice, 'conversation-1');
    await preferences.setString(cacheKey, '{not-json');

    expect(await store.read(alice, 'conversation-1'), isEmpty);
    expect(preferences.containsKey(cacheKey), isFalse);
  });

  test('领域消息序列化保持既有缓存字段契约', () {
    const message = ChatMessage(
      id: 'message-1',
      clientMessageId: 'client-message-1',
      conversationId: 'conversation-1',
      sequence: 7,
      author: 'Alice',
      authorId: 'alice',
      text: '正文',
      contentType: 'text',
      mine: true,
      replyTo: MessageReply(
          id: 'reply-1',
          author: 'Bob',
          authorId: 'bob',
          text: '引用',
          sequence: 6),
    );

    expect(messageCacheRecord(message), containsPair('sequence', 7));
    expect(messageCacheRecord(message),
        containsPair('client_message_id', 'client-message-1'));
    expect(messageCacheRecord(message), containsPair('author_id', 'alice'));
    expect(messageCacheRecord(message)['reply_to'], {
      'id': 'reply-1',
      'author': 'Bob',
      'author_id': 'bob',
      'sequence': 6,
      'text': '引用',
    });
  });
}

Map<String, dynamic> _message(
  String id,
  int sequence,
  String text, {
  String author = '成员',
  String authorId = 'member',
  String contentType = 'text',
  String createdAt = '2026-09-04T10:00:00Z',
}) =>
    {
      'id': id,
      'author': author,
      'author_id': authorId,
      'sequence': sequence,
      'created_at': createdAt,
      'content_type': contentType,
      'raw_body': {'type': contentType, 'content': text},
      'text': text,
      'mine': false,
      'reactions': const [],
    };
