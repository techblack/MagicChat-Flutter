import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/contact_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('联系人缓存保留群组和应用资料字段', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ContactCacheStore();
    await store.clearAll();
    const scope =
        MessageCacheScope(serverUrl: 'https://chat.example.com', userId: 'me');

    await store.write(scope, const [
      Contact(
          id: 'group-1',
          name: '项目群',
          type: 'group',
          joined: true,
          memberCount: 8,
          visibility: 'public'),
      Contact(
          id: 'app-1',
          name: '智能助手',
          type: 'app',
          description: '帮助整理会话',
          creatorUserId: 'creator-1'),
    ]);

    final values = await store.read(scope);
    final group = values.where((item) => item.id == 'group-1').single;
    final app = values.where((item) => item.id == 'app-1').single;
    expect(group.type, 'group');
    expect(group.joined, isTrue);
    expect(group.memberCount, 8);
    expect(group.visibility, 'public');
    expect(app.description, '帮助整理会话');
    expect(app.creatorUserId, 'creator-1');
  });
}
