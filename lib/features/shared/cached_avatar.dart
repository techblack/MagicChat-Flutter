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
    this.foregroundColor,
    this.borderRadius,
    super.key,
  });

  final MagicChatRepository repository;
  final String name;
  final Uri? avatarUri;
  final MessageCacheScope? cacheScope;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BorderRadius? borderRadius;

  @override
  State<CachedAvatar> createState() => _CachedAvatarState();
}

class _CachedAvatarState extends State<CachedAvatar> {
  static final _inFlight = <String, Future<Uint8List?>>{};
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
    _bytes = _cache.peek(_cacheKey);
    _startLoading();
  }

  @override
  void didUpdateWidget(covariant CachedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUri != widget.avatarUri ||
        oldWidget.cacheScope != widget.cacheScope) {
      _bytes = _cache.peek(_cacheKey);
      _startLoading();
    }
  }

  void _startLoading() {
    if (widget.avatarUri == null || _bytes != null) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    final uri = widget.avatarUri;
    if (uri == null) return;
    final key = _cacheKey;
    final future = _inFlight[key] ??= _loadBytes(key, uri);
    try {
      final bytes = await future;
      if (bytes != null && mounted && key == _cacheKey) {
        setState(() => _bytes = bytes);
      }
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  Future<Uint8List?> _loadBytes(String key, Uri uri) async {
    try {
      final cached = await _cache.read(key);
      if (cached != null) return cached;
      final bytes = await widget.repository.downloadResource(uri);
      if (bytes == null || bytes.isEmpty) return null;
      try {
        await _cache.write(key, bytes);
      } catch (_) {
        // 资源仍可直接显示，缓存目录不可写不阻断会话。
      }
      return bytes;
    } catch (_) {
      // 首屏仍使用 NetworkImage 作为在线回退，缓存失败不影响头像显示。
      return null;
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
    final backgroundColor = widget.backgroundColor ??
        Theme.of(context).colorScheme.primaryContainer;
    final foregroundColor = widget.foregroundColor ??
        Theme.of(context).colorScheme.onPrimaryContainer;
    final fallback = image == null
        ? label.isEmpty
            ? const Icon(Icons.person_outline, size: 17)
            : Text(label.characters.first)
        : null;
    final borderRadius = widget.borderRadius;
    if (borderRadius == null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        backgroundImage: image,
        child: fallback,
      );
    }
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: IconTheme(
        data: IconThemeData(color: foregroundColor),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foregroundColor),
          child: fallback ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
