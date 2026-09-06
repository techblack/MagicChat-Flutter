import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/desktop_tray_model.dart';
import 'package:magicchat_client/domain/models.dart';

void main() {
  test('托盘按最新未读会话排序并展示预览', () {
    final items = desktopTrayMessages(const [
      ChatConversation(
          id: 'older',
          title: '旧会话',
          preview: '较早内容',
          unread: 2,
          lastMessageAt: '2026-09-05T08:00:00Z'),
      ChatConversation(
          id: 'newer',
          title: '新会话',
          preview: '最新内容',
          unread: 3,
          lastMessageAt: '2026-09-06T08:00:00Z'),
      ChatConversation(id: 'read', title: '已读会话'),
    ], MessageNotificationPrivacy.preview);

    expect(items.map((item) => item.conversationId), ['newer', 'older']);
    expect(items.first.label, '新会话  [3] — 最新内容');
  });

  test('隐藏通知内容时托盘不暴露会话名称和消息正文', () {
    final item = desktopTrayMessages(const [
      ChatConversation(
          id: 'secret', title: '机密项目', preview: '机密正文', unread: 120),
    ], MessageNotificationPrivacy.hidden)
        .single;

    expect(item.label, '新消息  [99+] — 你收到了一条新消息');
    expect(item.label, isNot(contains('机密')));
  });

  test('托盘预览将提及标记替换为联系人名称', () {
    final item = desktopTrayMessages(
      const [
        ChatConversation(
            id: 'mentions',
            title: '研发群',
            preview: '{(@user/alice)} 请查看',
            unread: 1),
      ],
      MessageNotificationPrivacy.preview,
      contacts: const {'alice': Contact(id: 'alice', name: 'Alice')},
    ).single;

    expect(item.label, '研发群  [1] — @Alice 请查看');
    expect(item.label, isNot(contains('alice)')));
  });

  test('托盘提示限制未读数范围', () {
    expect(desktopTrayToolTip(0), 'MagicChat');
    expect(desktopTrayToolTip(12000), 'MagicChat（9999 条未读）');
  });

  test('托盘预览按提及 ID 查找联系人，不遍历 2000 人目录', () {
    final contacts = _LookupOnlyContactMap({
      for (var index = 0; index < 2000; index++)
        'user-$index': Contact(id: 'user-$index', name: '成员 $index'),
    });

    final item = desktopTrayMessages(
      const [
        ChatConversation(
            id: 'mentions',
            title: '群聊',
            preview: '{(@user/user-1999)} 请查看',
            unread: 1),
      ],
      MessageNotificationPrivacy.preview,
      contacts: contacts,
    ).single;

    expect(item.label, contains('@成员 1999'));
    expect(contacts.lookups, 1);
  });
}

class _LookupOnlyContactMap extends MapBase<String, Contact> {
  _LookupOnlyContactMap(this._values);

  final Map<String, Contact> _values;
  int lookups = 0;

  @override
  Contact? operator [](Object? key) {
    lookups++;
    return _values[key];
  }

  @override
  void operator []=(String key, Contact value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Iterable<String> get keys => throw StateError('不应遍历完整联系人 Map');

  @override
  Contact? remove(Object? key) => throw UnsupportedError('read only');
}
