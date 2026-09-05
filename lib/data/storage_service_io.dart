import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'asset_cache_store.dart';
import 'message_cache_store.dart';
import 'storage_service_types.dart';

class StorageService {
  StorageService(
      {MessageCacheStore? messageCacheStore,
      LocalAssetCache? assetCacheStore,
      String? temporaryDirectoryPath,
      String? applicationSupportDirectoryPath})
      : _messageCacheStore = messageCacheStore ?? MessageCacheStore(),
        _assetCacheStore = assetCacheStore ?? LocalAssetCache(),
        _temporaryDirectoryPath = temporaryDirectoryPath,
        _applicationSupportDirectoryPath = applicationSupportDirectoryPath;

  final MessageCacheStore _messageCacheStore;
  final LocalAssetCache _assetCacheStore;
  final String? _temporaryDirectoryPath;
  final String? _applicationSupportDirectoryPath;

  Future<Directory> _temporaryDirectory() async {
    final path = _temporaryDirectoryPath;
    return path == null ? await getTemporaryDirectory() : Directory(path);
  }

  Future<Directory> _applicationSupportDirectory() async {
    final path = _applicationSupportDirectoryPath;
    return path == null
        ? await getApplicationSupportDirectory()
        : Directory(path);
  }

  Future<Directory> _assetDirectory() async => Directory(
      '${(await _applicationSupportDirectory()).path}/${LocalAssetCache.directoryName}');

  Future<Directory> _messageDirectory() async =>
      Directory('${(await _applicationSupportDirectory()).path}/message-cache');

  Future<StorageInfo> inspect() async {
    final temporary = await _temporaryDirectory();
    final assets = await _assetDirectory();
    final messages = await _messageDirectory();
    return StorageInfo(
      mediaBytes: _size(temporary) + _size(assets),
      messageBytes: _size(messages),
    );
  }

  Future<void> clear(StoragePart part) async {
    if (part == StoragePart.media || part == StoragePart.all) {
      await _assetCacheStore.clearAll();
      await _clearDirectory(await _assetDirectory());
      await _clearDirectory(await _temporaryDirectory());
    }
    if (part == StoragePart.messages || part == StoragePart.all) {
      await _messageCacheStore.clearAll();
    }
  }

  Future<void> clearCache() => clear(StoragePart.all);

  Future<void> _clearDirectory(Directory directory) async {
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      await entity.delete(recursive: true);
    }
  }

  int _size(FileSystemEntity entity) {
    if (!entity.existsSync()) return 0;
    if (entity is File) return entity.lengthSync();
    if (entity is Directory) {
      return entity.listSync().fold<int>(0, (sum, item) => sum + _size(item));
    }
    return 0;
  }
}
