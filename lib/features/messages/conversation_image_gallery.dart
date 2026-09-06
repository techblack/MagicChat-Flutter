import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/asset_cache_store.dart';
import '../../data/image_save_service.dart';
import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/user_facing_error.dart';

typedef ConversationImageSaver = Future<ImageSaveResult> Function(
    Uint8List bytes, String suggestedName, int fallbackIndex);

class ConversationGalleryImage {
  const ConversationGalleryImage({
    required this.messageId,
    required this.fileId,
    required this.sequence,
    this.caption = '',
    this.name = '',
  });

  final String messageId;
  final String fileId;
  final int sequence;
  final String caption;
  final String name;
}

List<ConversationGalleryImage> buildConversationImageGallery(
    Iterable<ChatMessage> messages) {
  final byMessage = <String, ConversationGalleryImage>{};
  for (final message in messages) {
    final fileId = message.rawBody['file_id'];
    if (message.contentType != 'image' ||
        message.id.isEmpty ||
        fileId is! String ||
        fileId.trim().isEmpty) {
      continue;
    }
    final caption = message.rawBody['caption'];
    final name = message.rawBody['name'];
    byMessage[message.id] = ConversationGalleryImage(
      messageId: message.id,
      fileId: fileId.trim(),
      sequence: message.sequence ?? 0,
      caption: caption is String ? caption.trim() : '',
      name: name is String ? name.trim() : '',
    );
  }
  final gallery = byMessage.values.toList(growable: false)
    ..sort((left, right) {
      final sequence = left.sequence.compareTo(right.sequence);
      return sequence == 0
          ? left.messageId.compareTo(right.messageId)
          : sequence;
    });
  return gallery;
}

Future<void> showConversationImageGallery(
  BuildContext context, {
  required MagicChatRepository repository,
  required String conversationId,
  required List<ChatMessage> messages,
  required String initialMessageId,
  required bool hasOlder,
  MessageCacheScope? cacheScope,
  Uint8List? initialBytes,
  Uri? initialUri,
  Future<void> Function(String messageId)? onForward,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: ConversationImageGallery(
          repository: repository,
          conversationId: conversationId,
          messages: messages,
          initialMessageId: initialMessageId,
          hasOlder: hasOlder,
          cacheScope: cacheScope,
          initialBytes: initialBytes,
          initialUri: initialUri,
          onForward: onForward,
        ),
      ),
    );

class ConversationImageGallery extends StatefulWidget {
  const ConversationImageGallery({
    required this.repository,
    required this.conversationId,
    required this.messages,
    required this.initialMessageId,
    required this.hasOlder,
    this.cacheScope,
    this.initialBytes,
    this.initialUri,
    this.onForward,
    this.imageSaver,
    super.key,
  });

  final MagicChatRepository repository;
  final String conversationId;
  final List<ChatMessage> messages;
  final String initialMessageId;
  final bool hasOlder;
  final MessageCacheScope? cacheScope;
  final Uint8List? initialBytes;
  final Uri? initialUri;
  final Future<void> Function(String messageId)? onForward;
  final ConversationImageSaver? imageSaver;

  @override
  State<ConversationImageGallery> createState() =>
      _ConversationImageGalleryState();
}

class _ConversationImageGalleryState extends State<ConversationImageGallery> {
  late List<ConversationGalleryImage> _images =
      buildConversationImageGallery(widget.messages);
  late String _currentMessageId = widget.initialMessageId;
  late bool _hasOlder = widget.hasOlder;
  final _resources = <String, Future<_GalleryResource>>{};
  TransformationController _transformationController =
      TransformationController();
  Offset? _pointerStart;
  bool _loadingOlder = false;
  bool _saving = false;
  bool _initialResourceInvalidated = false;

  int get _currentIndex =>
      _images.indexWhere((image) => image.messageId == _currentMessageId);

  ConversationGalleryImage? get _current {
    final index = _currentIndex;
    return index < 0 ? null : _images[index];
  }

  @override
  void initState() {
    super.initState();
    if (_current == null && _images.isNotEmpty) {
      _currentMessageId = _images.last.messageId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchAdjacent());
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _select(ConversationGalleryImage image) {
    if (image.messageId == _currentMessageId) return;
    final previousController = _transformationController;
    _transformationController = TransformationController();
    setState(() => _currentMessageId = image.messageId);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => previousController.dispose());
    _prefetchAdjacent();
  }

  Future<void> _previous() async {
    final index = _currentIndex;
    if (index > 0) {
      _select(_images[index - 1]);
      return;
    }
    if (!_hasOlder || _loadingOlder) return;
    await _findOlderImage();
  }

  void _next() {
    final index = _currentIndex;
    if (index >= 0 && index + 1 < _images.length) {
      _select(_images[index + 1]);
    }
  }

  Future<void> _findOlderImage() async {
    setState(() => _loadingOlder = true);
    try {
      var before = _images
          .where((image) => image.sequence > 0)
          .map((image) => image.sequence)
          .fold<int?>(
              null,
              (value, sequence) =>
                  value == null ? sequence : min(value, sequence));
      while (_hasOlder && mounted) {
        final requestBefore = before;
        if (requestBefore == null || requestBefore <= 1) {
          _hasOlder = false;
          break;
        }
        final page = await widget.repository.messages(widget.conversationId,
            beforeSeq: requestBefore, limit: 50);
        final olderImages = buildConversationImageGallery(page);
        final known = _images.map((image) => image.messageId).toSet();
        final added = olderImages
            .where((image) => known.add(image.messageId))
            .toList(growable: false);
        final nextBefore = page
            .where((message) => (message.sequence ?? 0) > 0)
            .map((message) => message.sequence!)
            .fold<int?>(
                null,
                (value, sequence) =>
                    value == null ? sequence : min(value, sequence));
        _hasOlder = page is MessagePage
            ? page.hasMoreBefore
            : nextBefore != null && nextBefore < requestBefore;
        if (added.isNotEmpty) {
          _images = [..._images, ...added]..sort((left, right) {
              final sequence = left.sequence.compareTo(right.sequence);
              return sequence == 0
                  ? left.messageId.compareTo(right.messageId)
                  : sequence;
            });
          final previous = _images
              .where((image) => image.sequence < requestBefore)
              .toList(growable: false);
          if (mounted && previous.isNotEmpty) {
            _select(previous.last);
            return;
          }
        }
        if (page.isEmpty) {
          _hasOlder = false;
          break;
        }
        if (nextBefore == null || nextBefore >= requestBefore) {
          _hasOlder = false;
          break;
        }
        before = nextBefore;
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showMessage('更早图片加载失败：${userFacingError(error)}');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _prefetchAdjacent() {
    if (!mounted) return;
    final index = _currentIndex;
    if (index < 0) return;
    for (final adjacent in [index - 1, index + 1]) {
      if (adjacent >= 0 && adjacent < _images.length) {
        unawaited(_resource(_images[adjacent]).catchError(
            (_) => _GalleryResource(fileId: _images[adjacent].fileId)));
      }
    }
  }

  Future<_GalleryResource> _resource(ConversationGalleryImage image) {
    return _resources.putIfAbsent(image.fileId, () {
      if (!_initialResourceInvalidated &&
          image.messageId == widget.initialMessageId &&
          (widget.initialBytes != null || widget.initialUri != null)) {
        return Future.value(_GalleryResource(
            fileId: image.fileId,
            bytes: widget.initialBytes,
            uri: widget.initialUri));
      }
      return _loadResource(image.fileId);
    });
  }

  Future<_GalleryResource> _loadResource(String fileId) async {
    final cache = LocalAssetCache();
    final key = _cacheKey(fileId);
    final cached = await cache.read(key);
    if (cached != null && cached.isNotEmpty) {
      return _GalleryResource(fileId: fileId, bytes: cached);
    }
    final uri = await widget.repository.attachmentUrl(fileId);
    Uint8List? bytes;
    if (uri != null) {
      try {
        bytes = await widget.repository.downloadResource(uri);
      } catch (_) {
        bytes = null;
      }
    }
    bytes ??= await widget.repository.downloadAttachment(fileId);
    if (bytes != null && bytes.isNotEmpty) {
      await cache.write(key, bytes);
    }
    if ((bytes == null || bytes.isEmpty) && uri == null) {
      throw StateError('图片加载失败');
    }
    return _GalleryResource(fileId: fileId, bytes: bytes, uri: uri);
  }

  Future<void> _retry(ConversationGalleryImage image) async {
    await LocalAssetCache().remove(_cacheKey(image.fileId));
    _resources.remove(image.fileId);
    if (image.messageId == widget.initialMessageId) {
      _initialResourceInvalidated = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final image = _current;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final resource = await _resource(image);
      final bytes = resource.bytes ??
          await widget.repository.downloadAttachment(image.fileId);
      if (bytes == null || bytes.isEmpty) throw StateError('图片内容为空');
      final result = await (widget.imageSaver ?? _saveImage)(bytes, image.name,
          image.sequence > 0 ? image.sequence : _currentIndex + 1);
      if (mounted && result.saved) _showMessage(result.message);
    } catch (error) {
      final reason =
          error is ImageSaveException ? error.message : userFacingError(error);
      if (mounted) _showMessage('保存图片失败：$reason');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ImageSaveResult> _saveImage(
          Uint8List bytes, String suggestedName, int fallbackIndex) =>
      const ImageSaveService().save(
        bytes,
        suggestedName: suggestedName,
        fallbackIndex: fallbackIndex,
      );

  Future<void> _forward() async {
    final image = _current;
    final forward = widget.onForward;
    if (image == null || forward == null) return;
    Navigator.pop(context);
    await forward(image.messageId);
  }

  String _cacheKey(String fileId) {
    final scope = widget.cacheScope;
    final owner = scope == null ? '' : '${scope.serverUrl}|${scope.userId}|';
    return 'attachment|$owner$fileId';
  }

  void _showMessage(String message) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      unawaited(_previous());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _next();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_transformationController.value.getMaxScaleOnAxis() <= 1.01) {
      _pointerStart = event.position;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _pointerStart;
    _pointerStart = null;
    if (start == null) return;
    final delta = event.position - start;
    if (delta.dx.abs() < 56 || delta.dx.abs() <= delta.dy.abs()) return;
    if (delta.dx < 0) {
      _next();
    } else {
      unawaited(_previous());
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _current;
    final index = _currentIndex;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          child: Stack(children: [
            Positioned.fill(
              child: image == null
                  ? const _GalleryMessage(text: '图片信息不存在')
                  : FutureBuilder<_GalleryResource>(
                      key: ValueKey('gallery-resource-${image.fileId}'),
                      future: _resource(image),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _GalleryMessage(
                              text: '图片加载失败',
                              action: '重新加载',
                              onAction: () => _retry(image));
                        }
                        final resource = snapshot.data;
                        if (resource == null) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white));
                        }
                        final picture = resource.bytes != null
                            ? Image.memory(resource.bytes!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => _GalleryMessage(
                                    text: '图片无法显示',
                                    action: '重新加载',
                                    onAction: () => _retry(image)))
                            : Image.network(resource.uri.toString(),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => _GalleryMessage(
                                    text: '图片无法显示',
                                    action: '重新加载',
                                    onAction: () => _retry(image)));
                        return InteractiveViewer(
                          key: ValueKey('gallery-image-${image.fileId}'),
                          transformationController: _transformationController,
                          minScale: .5,
                          maxScale: 6,
                          boundaryMargin: const EdgeInsets.all(80),
                          child: Center(child: picture),
                        );
                      },
                    ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Row(children: [
                    IconButton(
                        tooltip: '关闭',
                        color: Colors.white,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                    Expanded(
                      child: Text(
                        image == null ? '' : '${index + 1} / ${_images.length}',
                        key: const ValueKey('gallery-counter'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: imageSaveActionLabel(),
                      color: Colors.white,
                      onPressed: image == null || _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.download_outlined),
                    ),
                    if (widget.onForward != null)
                      IconButton(
                          tooltip: '转发图片',
                          color: Colors.white,
                          onPressed: image == null ? null : _forward,
                          icon: const Icon(Icons.forward_outlined)),
                  ]),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                key: const ValueKey('gallery-previous'),
                tooltip: '上一张',
                onPressed: index > 0 || _hasOlder ? _previous : null,
                icon: _loadingOlder
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_left),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton.filledTonal(
                key: const ValueKey('gallery-next'),
                tooltip: '下一张',
                onPressed:
                    index >= 0 && index + 1 < _images.length ? _next : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
            if (image?.caption.isNotEmpty == true)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black54,
                    padding: const EdgeInsets.all(12),
                    child: Text(image!.caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _GalleryResource {
  const _GalleryResource({required this.fileId, this.bytes, this.uri});

  final String fileId;
  final Uint8List? bytes;
  final Uri? uri;
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: const TextStyle(color: Colors.white)),
          if (action != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ]),
      );
}
