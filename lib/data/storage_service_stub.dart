import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
        _assetCacheStore = assetCacheStore ?? LocalAssetCache();

  final MessageCacheStore _messageCacheStore;
  final LocalAssetCache _assetCacheStore;

  Future<StorageInfo> inspect() async {
    final preferences = await SharedPreferences.getInstance();
    var mediaBytes = 0;
    var messageBytes = 0;
    for (final key in preferences.getKeys()) {
      final value = preferences.getString(key);
      if (value == null) continue;
      final bytes = utf8.encode(key).length + utf8.encode(value).length;
      if (key.startsWith(LocalAssetCache.keyPrefix)) {
        mediaBytes += bytes;
      } else if (key.startsWith(MessageCacheStore.keyPrefix) ||
          key.startsWith(MessageCacheStore.legacyKeyPrefix)) {
        messageBytes += bytes;
      }
    }
    return StorageInfo(mediaBytes: mediaBytes, messageBytes: messageBytes);
  }

  Future<StorageClearResult> clear(StoragePart part) async {
    final targets = part == StoragePart.all
        ? const [StoragePart.media, StoragePart.messages]
        : [part];
    final cleared = <StoragePart>{};
    final failed = <StoragePart>{};
    for (final target in targets) {
      try {
        if (target == StoragePart.media) {
          await _assetCacheStore.clearAll();
        } else {
          await _messageCacheStore.clearAll();
        }
        cleared.add(target);
      } catch (_) {
        failed.add(target);
      }
    }
    return StorageClearResult(cleared: cleared, failed: failed);
  }

  Future<StorageClearResult> clearCache() => clear(StoragePart.all);
}
