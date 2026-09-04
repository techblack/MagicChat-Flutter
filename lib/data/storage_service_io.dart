import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'message_cache_store.dart';
import 'contact_cache_store.dart';

class StorageInfo {
  const StorageInfo({required this.path, required this.bytes});
  final String path;
  final int bytes;
  String get formatted {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

class StorageService {
  StorageService({MessageCacheStore? messageCacheStore})
      : _messageCacheStore = messageCacheStore ?? MessageCacheStore();

  final MessageCacheStore _messageCacheStore;
  final ContactCacheStore _contactCacheStore = ContactCacheStore();

  Future<Directory> _cacheDirectory() async => getTemporaryDirectory();
  Future<Directory> _messageCacheDirectory() async => Directory(
      '${(await getApplicationSupportDirectory()).path}/message-cache');
  Future<StorageInfo> inspect() async {
    final temporary = await _cacheDirectory();
    final messages = await _messageCacheDirectory();
    return StorageInfo(
        path: '${temporary.path}\n${messages.path}',
        bytes: _size(temporary) + _size(messages));
  }

  Future<void> clearCache() async {
    await _messageCacheStore.clearAll();
    await _contactCacheStore.clearAll();
    final directory = await _cacheDirectory();
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  int _size(FileSystemEntity entity) {
    if (!entity.existsSync()) return 0;
    if (entity is File) return entity.lengthSync();
    if (entity is Directory)
      return entity.listSync().fold<int>(0, (sum, item) => sum + _size(item));
    return 0;
  }
}
