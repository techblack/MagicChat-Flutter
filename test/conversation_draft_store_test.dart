import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/conversation_draft_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const alice = MessageCacheScope(
    serverUrl: 'https://chat.example.com',
    userId: 'alice',
  );
  const bob = MessageCacheScope(
    serverUrl: 'https://chat.example.com',
    userId: 'bob',
  );
  const otherServer = MessageCacheScope(
    serverUrl: 'https://other.example.com',
    userId: 'alice',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('草稿按 Server 和账号隔离并保留回复与 Markdown 模式', () async {
    final writer = ConversationDraftStore();
    await writer.load(alice);
    writer.update(
      'conversation-1',
      text: '# 发布计划',
      markdownMode: true,
      replyTo: const MessageReply(
        id: 'message-1',
        author: 'Alice',
        authorId: 'alice',
        text: '原消息',
      ),
    );
    await writer.flush();

    final reader = ConversationDraftStore();
    await reader.load(alice);
    expect(reader.draftFor('conversation-1')?.text, '# 发布计划');
    expect(reader.draftFor('conversation-1')?.markdownMode, isTrue);
    expect(reader.draftFor('conversation-1')?.replyTo?.id, 'message-1');

    await reader.load(bob);
    expect(reader.draftFor('conversation-1'), isNull);
    await reader.load(otherServer);
    expect(reader.draftFor('conversation-1'), isNull);

    writer.dispose();
    reader.dispose();
  });

  test('空草稿会移除且超过七天的草稿会在读取时清理', () async {
    final old = DateTime(2026, 8, 1);
    final writer = ConversationDraftStore();
    await writer.load(alice, now: old);
    writer.update('expired', text: '旧草稿', markdownMode: false, now: old);
    writer.update('removed', text: '临时内容', markdownMode: false, now: old);
    writer.update('removed', text: '', markdownMode: false, now: old);
    await writer.flush();

    final reader = ConversationDraftStore();
    await reader.load(alice, now: old.add(const Duration(days: 8)));
    expect(reader.draftFor('expired'), isNull);
    expect(reader.draftFor('removed'), isNull);
    await reader.flush();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
            (key) => key.startsWith('magicchat.conversation-drafts.v1.'),
          ),
      isEmpty,
    );

    writer.dispose();
    reader.dispose();
  });

  test('连续输入只发送一次侧栏通知，清空时立即通知', () async {
    final store = ConversationDraftStore();
    await store.load(alice);
    var notifications = 0;
    store.addListener(() => notifications++);

    store.update('conversation-1', text: '草', markdownMode: false);
    store.update('conversation-1', text: '草稿', markdownMode: false);
    store.update('conversation-1', text: '草稿内容', markdownMode: false);
    expect(notifications, 0);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(notifications, 1);

    store.clear('conversation-1');
    expect(notifications, 2);
    await store.flush();
    store.dispose();
  });
}
