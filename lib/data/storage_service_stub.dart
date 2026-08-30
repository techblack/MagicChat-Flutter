import 'message_cache_store.dart';
import 'contact_cache_store.dart';

class StorageInfo {
  const StorageInfo({required this.path, required this.bytes});
  final String path;
  final int bytes;
  String get formatted => '$bytes B';
}

class StorageService {
  StorageService({MessageCacheStore? messageCacheStore})
      : _messageCacheStore = messageCacheStore ?? MessageCacheStore();

  final MessageCacheStore _messageCacheStore;
  final ContactCacheStore _contactCacheStore = ContactCacheStore();

  Future<StorageInfo> inspect() async =>
      const StorageInfo(path: '浏览器缓存', bytes: 0);
  Future<void> clearCache() async {
    await _messageCacheStore.clearAll();
    await _contactCacheStore.clearAll();
  }
}
