import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Web 没有 dart:io 文件目录，使用本地存储保存小型头像/附件缓存。
class LocalAssetCache {
  static const directoryName = 'magicchat-assets-v1';
  static const keyPrefix = 'magicchat.asset-cache.v1.';
  static final _memory = <String, Uint8List>{};

  String _key(String value) =>
      '$keyPrefix${base64Url.encode(utf8.encode(value)).replaceAll('=', '')}';

  Future<Uint8List?> read(String key) async {
    final memory = _memory[key];
    if (memory != null) return Uint8List.fromList(memory);
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key(key));
    if (encoded == null) return null;
    try {
      final bytes = Uint8List.fromList(base64Decode(encoded));
      _memory[key] = bytes;
      return Uint8List.fromList(bytes);
    } catch (_) {
      await prefs.remove(_key(key));
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final copy = Uint8List.fromList(bytes);
    _memory[key] = copy;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), base64Encode(copy));
  }

  Future<void> remove(String key) async {
    _memory.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(key));
  }

  Future<void> clearAll() async {
    _memory.clear();
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs.getKeys().where((key) => key.startsWith(keyPrefix))) {
      await prefs.remove(key);
    }
  }
}
