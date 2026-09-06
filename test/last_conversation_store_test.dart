import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/last_conversation_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = LastConversationStore();
  const first = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-1');
  const second = MessageCacheScope(
      serverUrl: 'https://chat.example.com', userId: 'user-2');

  test('最近会话按 Server 和账号隔离保存', () async {
    SharedPreferences.setMockInitialValues({});

    await store.write(first, ' conversation-1 ');
    await store.write(second, 'conversation-2');

    expect(await store.read(first), 'conversation-1');
    expect(await store.read(second), 'conversation-2');
  });

  test('无效最近会话会清理且仅删除匹配会话', () async {
    SharedPreferences.setMockInitialValues({});
    await store.write(first, 'conversation-1');
    await store.clearIfMatches(first, 'other');
    expect(await store.read(first), 'conversation-1');

    await store.clearIfMatches(first, 'conversation-1');
    expect(await store.read(first), isEmpty);

    await store.write(first, 'x' * 513);
    expect(await store.read(first), isEmpty);
  });
}
