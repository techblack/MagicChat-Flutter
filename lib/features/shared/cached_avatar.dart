import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/asset_cache_store.dart';
import '../../data/message_cache_store.dart';
import '../../data/repository.dart';

/// 头像优先从磁盘读取，首次加载成功后写入本地缓存。
class CachedAvatar extends StatefulWidget {
  const CachedAvatar({
    required this.repository,
    required this.name,
    this.avatarUri,
    this.cacheScope,
    this.radius = 16,
    this.backgroundColor,
    super.key,
  });

  final MagicChatRepository repository;
  final String name;
  final Uri? avatarUri;
  final MessageCacheScope? cacheScope;
  final double radius;
  final Color? backgroundColor;

  @override
  State<CachedAvatar> createState() => _CachedAvatarState();
}

class _CachedAvatarState extends State<CachedAvatar> {
  final _cache = LocalAssetCache();
  Uint8List? _bytes;

  String get _cacheKey {
    final scope = widget.cacheScope;
    final owner = scope == null ? '' : '${scope.serverUrl}|${scope.userId}|';
    return 'avatar|$owner${widget.avatarUri}';
  }

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void didUpdateWidget(covariant CachedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUri != widget.avatarUri ||
        oldWidget.cacheScope != widget.cacheScope) {
      _bytes = null;
      _startLoading();
    }
  }

  void _startLoading() {
    if (widget.avatarUri == null) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    Uint8List? cached;
    try {
      cached = await _cache.read(_cacheKey);
    } catch (_) {
      cached = null;
    }
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    try {
      final bytes = await widget.repository.downloadResource(widget.avatarUri!);
      if (bytes == null || bytes.isEmpty) return;
      try {
        await _cache.write(_cacheKey, bytes);
      } catch (_) {
        // 资源仍可直接显示，缓存目录不可写不阻断会话。
      }
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      // 首屏仍使用 NetworkImage 作为在线回退，缓存失败不影响头像显示。
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.name.trim();
    ImageProvider<Object>? image;
    if (_bytes != null) {
      image = MemoryImage(_bytes!);
    } else if (widget.avatarUri != null) {
      image = NetworkImage(widget.avatarUri.toString());
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor ??
          Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: image,
      child: image == null
          ? label.isEmpty
              ? const Icon(Icons.person_outline, size: 17)
              : Text(label.characters.first)
          : null,
    );
  }
}
