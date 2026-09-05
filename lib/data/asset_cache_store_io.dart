import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 持久化头像和会话附件，文件名由资源键编码而来，不把原始 URL 暴露到文件名。
class LocalAssetCache {
  static const directoryName = 'magicchat-assets-v1';
  static const keyPrefix = 'magicchat.asset-cache.v1.';
  static final _memory = <String, Uint8List>{};
  static Directory? _directory;

  Future<Directory> _assetDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/$directoryName');
    await directory.create(recursive: true);
    _directory = directory;
    return directory;
  }

  String _fileName(String key) {
    final encoded = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    if (encoded.length <= 180) return encoded;
    return '${encoded.substring(0, 140)}-${key.hashCode.toRadixString(16)}';
  }

  Future<Uint8List?> read(String key) async {
    final memory = _memory[key];
    if (memory != null) return Uint8List.fromList(memory);
    final file = File('${(await _assetDirectory()).path}/${_fileName(key)}');
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      _memory[key] = bytes;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final copy = Uint8List.fromList(bytes);
    _memory[key] = copy;
    final file = File('${(await _assetDirectory()).path}/${_fileName(key)}');
    await file.writeAsBytes(copy, flush: true);
  }

  /// 读取当前进程内的缓存副本，供首帧渲染复用，避免页面切换时先闪回网络头像。
  Uint8List? peek(String key) {
    final bytes = _memory[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  void writeMemory(String key, Uint8List bytes) {
    if (bytes.isNotEmpty) _memory[key] = Uint8List.fromList(bytes);
  }

  void removeMemory(String key) => _memory.remove(key);

  Future<void> remove(String key) async {
    _memory.remove(key);
    final file = File('${(await _assetDirectory()).path}/${_fileName(key)}');
    if (await file.exists()) await file.delete();
  }

  Future<void> clearAll() async {
    _memory.clear();
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _directory = null;
  }
}
