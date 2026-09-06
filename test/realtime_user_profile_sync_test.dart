import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/contact_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/realtime_user_profile_sync.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('资料事件只刷新已知用户并精确替换本地缓存', () async {
    final repository = _ProfileRepository()
      ..profiles = const [
        Contact(
          id: 'user-1',
          name: '新名称',
          email: 'new@example.com',
          avatar: '',
        ),
      ];
    final store = RealtimeStore()
      ..contacts['user-1'] = const Contact(
        id: 'user-1',
        name: '旧名称',
        nickname: '旧昵称',
        avatar: '/old.webp',
      );
    const scope = MessageCacheScope(
      serverUrl: 'https://profile-sync.example.com',
      userId: 'me',
    );
    final cache = ContactCacheStore();
    await cache.write(scope, store.contacts.values);
    final sync = RealtimeUserProfileSync(
      repository: repository,
      store: store,
      cacheScope: () => scope,
      contactCacheStore: cache,
    );

    await sync.handle({
      'event': 'user.profile.updated',
      'payload': {'user_id': 'user-1', 'updated_at': '2026-09-07T12:00:00Z'},
    });
    await sync.handle({
      'event': 'user.profile.updated',
      'payload': {'user_id': 'unknown', 'updated_at': '2026-09-07T12:01:00Z'},
    });

    expect(repository.requests, [
      ['user-1'],
    ]);
    expect(store.contacts['user-1']?.displayName, '新名称');
    expect(store.contacts['user-1']?.nickname, isEmpty);
    expect(store.contacts['user-1']?.avatar, isEmpty);
    final cached = (await cache.read(scope)).single;
    expect(cached.nickname, isEmpty);
    expect(cached.avatar, isEmpty);
    sync.dispose();
  });

  test('同一用户连续更新时只采用最后一次请求结果', () async {
    final first = Completer<List<Contact>>();
    final second = Completer<List<Contact>>();
    final repository = _ProfileRepository()
      ..pendingResponses.addAll([first, second]);
    final store = RealtimeStore()
      ..contacts['user-1'] = const Contact(id: 'user-1', name: '旧名称');
    final sync = RealtimeUserProfileSync(
      repository: repository,
      store: store,
      cacheScope: () => null,
    );

    final firstRefresh = sync.handle({
      'event': 'user.profile.updated',
      'payload': {'user_id': 'user-1', 'updated_at': '2026-09-07T12:00:00Z'},
    });
    final secondRefresh = sync.handle({
      'event': 'user.profile.updated',
      'payload': {'user_id': 'user-1', 'updated_at': '2026-09-07T12:01:00Z'},
    });
    second.complete(const [
      Contact(id: 'user-1', name: '最新名称', avatar: '/new.webp'),
    ]);
    await secondRefresh;
    first.complete(const [Contact(id: 'user-1', name: '过期名称')]);
    await firstRefresh;
    await sync.handle({
      'event': 'user.profile.updated',
      'payload': {
        'user_id': 'user-1',
        'updated_at': '2026-09-07T12:00:00Z',
      },
    });

    expect(store.contacts['user-1']?.displayName, '最新名称');
    expect(store.userProfileRevision, 1);
    expect(repository.requests, hasLength(2));
    sync.dispose();
  });
}

class _ProfileRepository extends DemoRepository {
  List<Contact> profiles = const [];
  final requests = <List<String>>[];
  final pendingResponses = <Completer<List<Contact>>>[];

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) {
    requests.add(List.of(userIds));
    if (pendingResponses.isNotEmpty) {
      return pendingResponses.removeAt(0).future;
    }
    return Future.value(profiles);
  }
}
