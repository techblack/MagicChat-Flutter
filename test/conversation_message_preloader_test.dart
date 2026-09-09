import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/conversation_message_preloader.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const scope =
      MessageCacheScope(serverUrl: 'https://chat.example.com', userId: 'me');

  late Directory directory;
  late MessageCacheStore cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('magicchat-preloader-');
    cache = MessageCacheStore(databaseDirectory: directory.path);
  });

  tearDown(() async {
    await cache.clearAll();
    await cache.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('只预热最近会话、跳过已有缓存并限制并发数', () async {
    final repository = _PreloaderRepository();
    await cache.write(
        scope, 'cached', [messageCacheRecord(_message('cached-message', 1))],
        conversationType: 'group');
    final preloader = ConversationMessagePreloader(
        repository: repository,
        cacheStore: cache,
        maxConcurrent: 2,
        maxConversations: 3,
        messageLimit: 7);

    await preloader.preload(
      scope: scope,
      conversations: [
        const ChatConversation(
            id: 'old', title: '旧会话', type: 'group', lastMessageSeq: 1),
        const ChatConversation(
            id: 'cached', title: '已有缓存', type: 'group', lastMessageSeq: 4),
        const ChatConversation(
            id: 'pinned', title: '置顶会话', type: 'group', pinned: true),
        const ChatConversation(
            id: 'latest', title: '最新会话', type: 'group', lastMessageSeq: 9),
        const ChatConversation(
            id: 'outside', title: '不应预热', type: 'group', lastMessageSeq: 2),
      ],
    );

    expect(repository.requestedIds, ['pinned', 'latest']);
    expect(repository.maximumActive, 2);
    expect(repository.receivedLimits, [7, 7]);
    expect(await cache.read(scope, 'pinned', conversationType: 'group'),
        isNotEmpty);
    expect(await cache.read(scope, 'latest', conversationType: 'group'),
        isNotEmpty);
    expect(
        await cache.read(scope, 'outside', conversationType: 'group'), isEmpty);
  });

  test('取消预热后不会把旧会话消息写入缓存', () async {
    final repository = _PreloaderRepository(block: true);
    final preloader = ConversationMessagePreloader(
        repository: repository,
        cacheStore: cache,
        maxConcurrent: 1,
        maxConversations: 1);
    final loading = preloader.preload(
      scope: scope,
      conversations: const [
        ChatConversation(id: 'stale', title: '旧会话', type: 'group'),
      ],
    );
    await repository.started.future;
    preloader.cancel();
    repository.release.complete();
    await loading;

    expect(
        await cache.read(scope, 'stale', conversationType: 'group'), isEmpty);
  });

  test('用户打开同一会话后，预热响应不会覆盖已有缓存', () async {
    final repository = _PreloaderRepository(block: true);
    final preloader = ConversationMessagePreloader(
        repository: repository,
        cacheStore: cache,
        maxConcurrent: 1,
        maxConversations: 1);
    final loading = preloader.preload(
      scope: scope,
      conversations: const [
        ChatConversation(id: 'active', title: '当前会话', type: 'group'),
      ],
    );
    await repository.started.future;
    await cache.write(
        scope, 'active', [messageCacheRecord(_message('fresh-message', 2))],
        conversationType: 'group');
    repository.release.complete();
    await loading;

    final records =
        await cache.read(scope, 'active', conversationType: 'group', limit: 10);
    expect(records.map((record) => record['id']), ['fresh-message']);
  });
}

ChatMessage _message(String id, int sequence) => ChatMessage(
      id: id,
      conversationId: 'conversation',
      sequence: sequence,
      author: '成员',
      text: '预热消息',
    );

class _PreloaderRepository extends DemoRepository {
  _PreloaderRepository({this.block = false});

  final bool block;
  final started = Completer<void>();
  final release = Completer<void>();
  final requestedIds = <String>[];
  final receivedLimits = <int>[];
  var active = 0;
  var maximumActive = 0;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50}) async {
    requestedIds.add(conversationId);
    receivedLimits.add(limit);
    active++;
    if (active > maximumActive) maximumActive = active;
    if (!started.isCompleted) started.complete();
    try {
      if (block) {
        await release.future;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return [_message('$conversationId-message', 1)];
    } finally {
      active--;
    }
  }
}
