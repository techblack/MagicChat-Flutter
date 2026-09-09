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
  bool _imageFailed = false;
  bool _loading = false;

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
      _loading = false;
      _bytes = _cache.peek(_cacheKey);
      _imageFailed = false;
      _startLoading();
    }
  }

  void _startLoading() {
    if (widget.avatarUri == null || _bytes != null || _loading) return;
    _loading = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final uri = widget.avatarUri;
    if (uri == null) return;
    final key = _cacheKey;
    final future = _inFlight[key] ??= _loadBytes(key, uri);
    try {
      final bytes = await future;
      if (!mounted || key != _cacheKey) return;
      setState(() {
        _loading = false;
        if (bytes != null) {
          _bytes = bytes;
          _imageFailed = false;
        }
      });
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
      if (mounted && key == _cacheKey && _loading) {
        setState(() {
          _loading = false;
          _imageFailed = true;
        });
      }
    }
  }

  Future<Uint8List?> _loadBytes(String key, Uri uri) async {
    Uint8List? cached;
    try {
      cached = await _cache.read(key);
    } catch (_) {
      // 缓存目录不可读时继续请求头像，缓存故障不应阻断资料展示。
    }
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final bytes = await widget.repository.downloadResource(uri);
      if (bytes == null || bytes.isEmpty) return null;
      try {
        await _cache.write(key, bytes);
      } catch (_) {
        // 资源仍可直接显示，缓存目录不可写不阻断会话。
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _handleImageError(Object _, StackTrace? __) {
    if (mounted && !_imageFailed) setState(() => _imageFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.name.trim();
    ImageProvider<Object>? image;
    if (!_imageFailed && _bytes != null) {
      image = MemoryImage(_bytes!);
    } else if (!_imageFailed && !_loading && widget.avatarUri != null) {
      // 只有鉴权缓存加载结束后才启用在线回退，避免首帧同时发起两次请求。
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
        onBackgroundImageError: image == null ? null : _handleImageError,
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
            : DecorationImage(
                image: image, fit: BoxFit.cover, onError: _handleImageError),
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
