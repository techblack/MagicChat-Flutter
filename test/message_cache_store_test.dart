import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const alice = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-alice');
  const bob = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-bob');
  const otherServer = MessageCacheScope(
      serverUrl: 'https://other.example.com', userId: 'user-alice');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('同一会话按账号和服务器隔离缓存', () async {
    final store = MessageCacheStore();
    await store.write(alice, 'conversation-1', [
      {'id': 'alice-message'}
    ]);
    await store.write(bob, 'conversation-1', [
      {'id': 'bob-message'}
    ]);

    expect((await store.read(alice, 'conversation-1')).single['id'],
        'alice-message');
    expect(
        (await store.read(bob, 'conversation-1')).single['id'], 'bob-message');
    expect(await store.read(otherServer, 'conversation-1'), isEmpty);
  });

  test('损坏 JSON 自动丢弃且不阻塞读取', () async {
    final store = MessageCacheStore();
    final prefs = await SharedPreferences.getInstance();
    final key = store.key(alice, 'conversation-1');
    await prefs.setString(key, '{not-json');

    expect(await store.read(alice, 'conversation-1'), isEmpty);
    expect(prefs.containsKey(key), isFalse);
  });

  test('清理缓存只删除消息缓存键', () async {
    final store = MessageCacheStore();
    final prefs = await SharedPreferences.getInstance();
    await store.write(alice, 'conversation-1', [
      {'id': 'message-1'}
    ]);
    await store.write(bob, 'conversation-2', [
      {'id': 'message-2'}
    ]);
    await prefs.setString('magicchat.messages.conversation-legacy', '[]');
    await prefs.setString('magicchat.document.document-1.draft', 'draft');

    await store.clearAll();

    expect(await store.read(alice, 'conversation-1'), isEmpty);
    expect(await store.read(bob, 'conversation-2'), isEmpty);
    expect(
        prefs.containsKey('magicchat.messages.conversation-legacy'), isFalse);
    expect(prefs.getString('magicchat.document.document-1.draft'), 'draft');
  });
}
