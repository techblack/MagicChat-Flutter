import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerExitEvent, PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:image/image.dart' as image;

import '../../data/desktop_screenshot.dart';
import '../../data/image_save_service.dart';
import '../../data/screenshot_clipboard_service.dart';
import '../../domain/screenshot_annotations.dart';

const screenshotAnnotationColors = <int>[
  0xffef4444,
  0xfff59e0b,
  0xff22c55e,
  0xff2563eb,
  0xffffffff,
];

typedef ScreenshotPngRenderer = FutureOr<Uint8List> Function(
    Uint8List sourceBytes, List<ScreenshotAnnotation> annotations);

Future<CapturedScreenshot?> showScreenshotAnnotationDialog(
        BuildContext context, CapturedScreenshot screenshot) =>
    showDialog<CapturedScreenshot>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScreenshotAnnotationDialog(screenshot: screenshot),
    );

class ScreenshotAnnotationDialog extends StatefulWidget {
  const ScreenshotAnnotationDialog({
    required this.screenshot,
    this.imageSaver,
    this.clipboardService,
    this.pngRenderer,
    super.key,
  });

  final CapturedScreenshot screenshot;
  final Future<ImageSaveResult> Function(
      Uint8List bytes, String suggestedName, int fallbackIndex)? imageSaver;
  final ScreenshotClipboardService? clipboardService;
  final ScreenshotPngRenderer? pngRenderer;

  @override
  State<ScreenshotAnnotationDialog> createState() =>
      _ScreenshotAnnotationDialogState();
}

class _ScreenshotAnnotationDialogState
    extends State<ScreenshotAnnotationDialog> {
  ScreenshotAnnotationHistory _history = const ScreenshotAnnotationHistory();
  ScreenshotAnnotationTool _tool = ScreenshotAnnotationTool.rectangle;
  ScreenshotAnnotation? _draft;
  ScreenshotAnnotation? _selected;
  ScreenshotAnnotation? _movingOriginal;
  ScreenshotAnnotation? _movePreview;
  ScreenshotAnnotationResizeHandle? _resizeHandle;
  ScreenshotAnnotationPoint? _start;
  ScreenshotAnnotationPoint? _cursor;
  List<ScreenshotAnnotationPoint> _brushPoints = const [];
  final FocusNode _keyboardFocusNode = FocusNode();
  int _color = screenshotAnnotationColors.first;
  bool _rendering = false;
  bool _saving = false;
  bool _copying = false;
  bool _preparingPng = false;
  String _error = '';
  late final int _imageWidth;
  late final int _imageHeight;
  late Uint8List? _cachedPngBytes;
  int _annotationVersion = 0;
  int _cachedPngVersion = 0;
  Future<void>? _preparingPngFuture;
  DesktopScreenshotException? _preparingPngError;

  @override
  void initState() {
    super.initState();
    final decoded = widget.screenshot.width > 0 && widget.screenshot.height > 0
        ? null
        : image.decodeImage(widget.screenshot.bytes);
    _imageWidth = widget.screenshot.width > 0
        ? widget.screenshot.width
        : decoded?.width ?? 1;
    _imageHeight = widget.screenshot.height > 0
        ? widget.screenshot.height
        : decoded?.height ?? 1;
    _cachedPngBytes = widget.screenshot.bytes;
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _undo() {
    setState(() {
      _history = _history.undo();
      _draft = null;
      _selected = null;
      _movingOriginal = null;
      _movePreview = null;
      _resizeHandle = null;
    });
    _prepareCurrentPng();
  }

  void _redo() {
    setState(() {
      _history = _history.redo();
      _draft = null;
      _selected = null;
      _movingOriginal = null;
      _movePreview = null;
      _resizeHandle = null;
    });
    _prepareCurrentPng();
  }

  void _startDrawing(DragStartDetails details, Size displaySize) {
    if (_rendering || _tool == ScreenshotAnnotationTool.text) return;
    final point = _imagePoint(details.localPosition, displaySize);
    setState(() => _cursor = point);
    if (_tool == ScreenshotAnnotationTool.select) {
      final current = _selected;
      final resizeHandle = current == null
          ? null
          : hitTestScreenshotAnnotationResizeHandle(
              annotation: current,
              point: point,
              imageSize: Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
              tolerance: 8 * _imageWidth / displaySize.width,
            );
      final selected =
          resizeHandle == null ? _annotationAt(point, displaySize) : current;
      setState(() {
        _selected = selected;
        _movingOriginal = selected;
        _movePreview = null;
        _resizeHandle = resizeHandle;
        _start = point;
        _draft = null;
      });
      _keyboardFocusNode.requestFocus();
      return;
    }
    setState(() {
      _start = point;
      _brushPoints = [point];
      _draft = null;
      _error = '';
    });
  }

  void _updateDrawing(DragUpdateDetails details, Size displaySize) {
    final start = _start;
    final point = _imagePoint(details.localPosition, displaySize);
    if (_rendering) return;
    if (start == null) {
      setState(() => _cursor = point);
      return;
    }
    final lineWidth = screenshotAnnotationLineWidth(
        displayWidth: displaySize.width, imageWidth: _imageWidth);
    setState(() {
      switch (_tool) {
        case ScreenshotAnnotationTool.select:
          final original = _movingOriginal;
          if (original != null) {
            final imageSize =
                Size(_imageWidth.toDouble(), _imageHeight.toDouble());
            final resizeHandle = _resizeHandle;
            _movePreview = resizeHandle == null
                ? translateScreenshotAnnotation(
                    annotation: original,
                    delta: Offset(point.x - start.x, point.y - start.y),
                    imageSize: imageSize,
                  )
                : resizeScreenshotAnnotation(
                    annotation: original,
                    handle: resizeHandle,
                    point: point,
                    imageSize: imageSize,
                  );
          }
          return;
        case ScreenshotAnnotationTool.rectangle:
          _draft = ScreenshotRectangleAnnotation(
              start: start, end: point, color: _color, lineWidth: lineWidth);
        case ScreenshotAnnotationTool.arrow:
          _draft = ScreenshotArrowAnnotation(
              start: start, end: point, color: _color, lineWidth: lineWidth);
        case ScreenshotAnnotationTool.brush:
          _brushPoints = [..._brushPoints, point];
          _draft = ScreenshotBrushAnnotation(
              points: _brushPoints, color: _color, lineWidth: lineWidth);
        case ScreenshotAnnotationTool.text:
          return;
        case ScreenshotAnnotationTool.mosaic:
          _draft = ScreenshotMosaicAnnotation(
              start: start, end: point, color: _color, lineWidth: lineWidth);
      }
    });
  }

  void _finishDrawing(DragEndDetails _) {
    if (_tool == ScreenshotAnnotationTool.select) {
      final original = _movingOriginal;
      final preview = _movePreview;
      var changed = false;
      setState(() {
        _cursor = null;
        if (original != null &&
            preview != null &&
            !identical(original, preview)) {
          _history = _history.replace(original, preview);
          _selected = preview;
          changed = true;
        }
        _movingOriginal = null;
        _movePreview = null;
        _resizeHandle = null;
        _start = null;
      });
      if (changed) _prepareCurrentPng();
      return;
    }
    final draft = _draft;
    var changed = false;
    setState(() {
      _cursor = null;
      if (draft != null && _isVisible(draft)) {
        _history = _history.commit(draft);
        changed = true;
      }
      _selected = null;
      _start = null;
      _brushPoints = const [];
      _draft = null;
      _movingOriginal = null;
      _movePreview = null;
      _resizeHandle = null;
    });
    if (changed) _prepareCurrentPng();
  }

  void _cancelDrawing() => setState(() {
        _cursor = null;
        _start = null;
        _brushPoints = const [];
        _draft = null;
        _movingOriginal = null;
        _movePreview = null;
        _resizeHandle = null;
      });

  Future<void> _addText(TapUpDetails details, Size displaySize) async {
    if (_rendering || _tool != ScreenshotAnnotationTool.text) return;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加文字'),
        content: TextField(
          key: const ValueKey('screenshot-text-input'),
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '输入标注内容'),
          onSubmitted: (value) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) Navigator.pop(context, normalized);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final normalized = controller.text.trim();
                if (normalized.isNotEmpty) Navigator.pop(context, normalized);
              },
              child: const Text('添加')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null) return;
    final point = _imagePoint(details.localPosition, displaySize);
    final fontSize = screenshotAnnotationFontSize(
        displayWidth: displaySize.width, imageWidth: _imageWidth);
    setState(() {
      _history = _history.commit(ScreenshotTextAnnotation(
          position: point, text: text, fontSize: fontSize, color: _color));
      _selected = null;
      _error = '';
    });
    _prepareCurrentPng();
  }

  void _handleCanvasTap(TapUpDetails details, Size displaySize) {
    if (_rendering) return;
    if (_tool == ScreenshotAnnotationTool.text) {
      _addText(details, displaySize);
      return;
    }
    if (_tool != ScreenshotAnnotationTool.select) return;
    final imagePoint = _imagePoint(details.localPosition, displaySize);
    setState(() {
      _selected = _annotationAt(imagePoint, displaySize);
      _movingOriginal = null;
      _movePreview = null;
      _resizeHandle = null;
    });
    _keyboardFocusNode.requestFocus();
  }

  void _updateCursor(PointerHoverEvent event, Size displaySize) {
    if (_rendering) return;
    final point = _imagePoint(event.localPosition, displaySize);
    if (point == _cursor) return;
    setState(() => _cursor = point);
  }

  void _clearCursor(PointerExitEvent event) {
    if (_start != null || _cursor == null) return;
    setState(() => _cursor = null);
  }

  ScreenshotAnnotation? _annotationAt(
          ScreenshotAnnotationPoint point, Size displaySize) =>
      hitTestScreenshotAnnotation(
        annotations: _history.present,
        point: point,
        imageSize: Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
        tolerance: 8 * _imageWidth / displaySize.width,
      );

  void _deleteSelected() {
    final selected = _selected;
    if (_rendering || selected == null) return;
    final next = _history.remove(selected);
    if (identical(next, _history)) return;
    setState(() {
      _history = next;
      _selected = null;
      _draft = null;
      _movingOriginal = null;
      _movePreview = null;
      _resizeHandle = null;
    });
    _prepareCurrentPng();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.delete &&
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_selected == null || _rendering) return KeyEventResult.ignored;
    _deleteSelected();
    return KeyEventResult.handled;
  }

  ScreenshotAnnotationPoint _imagePoint(Offset point, Size displaySize) =>
      screenshotImagePointFromDisplay(
        x: point.dx,
        y: point.dy,
        displayWidth: displaySize.width,
        displayHeight: displaySize.height,
        imageWidth: _imageWidth,
        imageHeight: _imageHeight,
      );

  bool _isVisible(ScreenshotAnnotation annotation) {
    if (annotation case ScreenshotBrushAnnotation brush) {
      return brush.points.length > 1;
    }
    if (annotation case ScreenshotTextAnnotation text) {
      return text.text.trim().isNotEmpty;
    }
    final (start, end) = switch (annotation) {
      ScreenshotRectangleAnnotation value => (value.start, value.end),
      ScreenshotArrowAnnotation value => (value.start, value.end),
      ScreenshotMosaicAnnotation value => (value.start, value.end),
      _ => throw StateError('不支持的截图标注'),
    };
    return math.sqrt(
            math.pow(end.x - start.x, 2) + math.pow(end.y - start.y, 2)) >=
        2;
  }

  Future<void> _finish() async {
    if (_rendering) return;
    if (_history.present.isEmpty) {
      Navigator.pop(context, widget.screenshot);
      return;
    }
    setState(() {
      _rendering = true;
      _error = '';
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final bytes = await _currentPngBytes();
      if (!mounted) return;
      Navigator.pop(
          context,
          CapturedScreenshot(
              bytes: bytes,
              width: _imageWidth,
              height: _imageHeight,
              fileName: widget.screenshot.fileName));
    } on DesktopScreenshotException catch (error) {
      if (mounted) {
        setState(() {
          _rendering = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _rendering = false;
          _error = '截图标注生成失败，请重试';
        });
      }
    }
  }

  Future<Uint8List> _renderBytes(List<ScreenshotAnnotation> annotations) async {
    final renderer = widget.pngRenderer;
    final rendered = renderer == null
        ? const ScreenshotAnnotationRenderer()
            .render(widget.screenshot.bytes, annotations)
        : renderer(widget.screenshot.bytes, annotations);
    final bytes = rendered is Future<Uint8List> ? await rendered : rendered;
    if (bytes.length > desktopScreenshotMaxImageBytes) {
      throw const DesktopScreenshotException(
        DesktopScreenshotErrorCode.imageTooLarge,
        '截图标注结果超过 32MiB，请减少标注或缩小截图区域',
      );
    }
    return bytes;
  }

  void _prepareCurrentPng() {
    final version = ++_annotationVersion;
    final annotations = List<ScreenshotAnnotation>.of(_history.present);
    _preparingPngError = null;
    if (annotations.isEmpty) {
      _preparingPngFuture = null;
      setState(() {
        _cachedPngBytes = widget.screenshot.bytes;
        _cachedPngVersion = version;
        _preparingPng = false;
        _error = '';
      });
      return;
    }
    setState(() {
      _cachedPngBytes = null;
      _preparingPng = true;
      _error = '';
    });
    final completion = Completer<void>();
    _preparingPngFuture = completion.future;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_preparePng(version, annotations).whenComplete(() {
        if (!completion.isCompleted) completion.complete();
      }));
    });
  }

  Future<void> _preparePng(
      int version, List<ScreenshotAnnotation> annotations) async {
    if (!mounted || version != _annotationVersion) return;
    try {
      final bytes = await _renderBytes(annotations);
      if (!mounted || version != _annotationVersion) return;
      setState(() {
        _cachedPngBytes = bytes;
        _cachedPngVersion = version;
        _preparingPng = false;
      });
    } on DesktopScreenshotException catch (error) {
      _completePngPreparationError(version, error);
    } catch (_) {
      _completePngPreparationError(
          version,
          const DesktopScreenshotException(
              DesktopScreenshotErrorCode.failed, '截图标注生成失败，请重试'));
    }
  }

  void _completePngPreparationError(
      int version, DesktopScreenshotException error) {
    if (!mounted || version != _annotationVersion) return;
    setState(() {
      _preparingPng = false;
      _preparingPngError = error;
      _error = error.message;
    });
  }

  Future<Uint8List> _currentPngBytes() async {
    final version = _annotationVersion;
    final cached = _cachedPngBytes;
    if (_cachedPngVersion == version && cached != null) return cached;
    final preparing = _preparingPngFuture;
    if (preparing != null) await preparing;
    final prepared = _cachedPngBytes;
    if (_cachedPngVersion == version && prepared != null) return prepared;
    throw _preparingPngError ??
        const DesktopScreenshotException(
            DesktopScreenshotErrorCode.failed, '截图标注生成失败，请重试');
  }

  Future<void> _save() async {
    if (_rendering) return;
    setState(() {
      _rendering = true;
      _saving = true;
      _error = '';
    });
    try {
      final bytes = await _currentPngBytes();
      final result = await (widget.imageSaver ?? _saveImage)(
          bytes, widget.screenshot.fileName, 1);
      if (mounted && result.saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } on ImageSaveException catch (error) {
      if (mounted) setState(() => _error = '保存截图失败：${error.message}');
    } on DesktopScreenshotException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '截图保存失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _rendering = false;
          _saving = false;
        });
      }
    }
  }

  Future<ImageSaveResult> _saveImage(
          Uint8List bytes, String suggestedName, int fallbackIndex) =>
      const ImageSaveService().save(bytes,
          suggestedName: suggestedName, fallbackIndex: fallbackIndex);

  Future<void> _copy() async {
    final bytes = _cachedPngBytes;
    if (_rendering ||
        _preparingPng ||
        bytes == null ||
        _cachedPngVersion != _annotationVersion) {
      return;
    }
    setState(() {
      _rendering = true;
      _copying = true;
      _error = '';
    });
    try {
      final write =
          (widget.clipboardService ?? const ScreenshotClipboardService())
              .copyPng(bytes, suggestedName: widget.screenshot.fileName);
      await write;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('截图已复制到剪贴板')));
      }
    } on ScreenshotClipboardException catch (error) {
      if (mounted) setState(() => _error = '复制截图失败：${error.message}');
    } catch (_) {
      if (mounted) setState(() => _error = '复制截图失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _rendering = false;
          _copying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_rendering,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: math.min(900, viewport.width - 24),
          height: math.min(720, math.max(320, viewport.height - 24)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text('发送截图',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Text(
                    '$_imageWidth × $_imageHeight · ${_formatBytes(widget.screenshot.bytes.length)}',
                    key: const ValueKey('screenshot-preview-metadata'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: Focus(
                    focusNode: _keyboardFocusNode,
                    autofocus: true,
                    onKeyEvent: _handleKeyEvent,
                    child: _annotationCanvas(),
                  ),
                ),
                const SizedBox(height: 12),
                _toolbar(),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_error,
                      key: const ValueKey('screenshot-annotation-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(
                    key: const ValueKey('screenshot-save'),
                    tooltip: imageSaveActionLabel(),
                    onPressed: _rendering ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    key: const ValueKey('screenshot-copy'),
                    tooltip: '复制截图',
                    onPressed: _rendering ||
                            _preparingPng ||
                            _cachedPngBytes == null ||
                            _cachedPngVersion != _annotationVersion
                        ? null
                        : _copy,
                    icon: _copying
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.copy_outlined),
                  ),
                  const Spacer(),
                  TextButton(
                      onPressed:
                          _rendering ? null : () => Navigator.pop(context),
                      child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _rendering ? null : _finish,
                    icon: _rendering && !_saving && !_copying
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: const Text('发送'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _annotationCanvas() => LayoutBuilder(builder: (context, constraints) {
        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
          constraints.biggest,
        );
        final rect = Alignment.center
            .inscribe(fitted.destination, Offset.zero & constraints.biggest);
        final displaySize = rect.size;
        final cursor = _cursor;
        final cursorDisplay = cursor == null
            ? null
            : Offset(
                cursor.x * displaySize.width / _imageWidth,
                cursor.y * displaySize.height / _imageHeight,
              );
        const magnifierSize = 116.0;
        final cursorCanvas = cursorDisplay == null
            ? null
            : Offset(rect.left + cursorDisplay.dx, rect.top + cursorDisplay.dy);
        final magnifierLeft = cursorCanvas == null
            ? 0.0
            : (cursorCanvas.dx + 20)
                .clamp(8.0, constraints.maxWidth - magnifierSize - 8);
        final magnifierTop = cursorCanvas == null
            ? 0.0
            : (cursorCanvas.dy + 20)
                .clamp(8.0, constraints.maxHeight - magnifierSize - 8);
        return Stack(children: [
          Positioned.fromRect(
            rect: rect,
            child: ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(widget.screenshot.bytes,
                    fit: BoxFit.fill, gaplessPlayback: true),
                MouseRegion(
                  onHover: (event) => _updateCursor(event, displaySize),
                  onExit: _clearCursor,
                  child: GestureDetector(
                    key: const ValueKey('screenshot-annotation-canvas'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (details) =>
                        _startDrawing(details, displaySize),
                    onPanUpdate: (details) =>
                        _updateDrawing(details, displaySize),
                    onPanEnd: _finishDrawing,
                    onPanCancel: _cancelDrawing,
                    onTapUp: (details) =>
                        _handleCanvasTap(details, displaySize),
                    child: CustomPaint(
                      painter: ScreenshotAnnotationPainter(
                        annotations: _history.present,
                        draft: _draft,
                        selected: _selected,
                        movePreview: _movePreview,
                        imageSize: Size(
                            _imageWidth.toDouble(), _imageHeight.toDouble()),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (cursorDisplay != null)
            Positioned(
              key: const ValueKey('screenshot-magnifier'),
              left: magnifierLeft.toDouble(),
              top: magnifierTop.toDouble(),
              width: magnifierSize,
              height: magnifierSize,
              child: IgnorePointer(
                child: _ScreenshotMagnifier(
                  bytes: widget.screenshot.bytes,
                  displaySize: displaySize,
                  center: cursorDisplay,
                ),
              ),
            ),
        ]);
      });

  Widget _toolbar() => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (tool, label, icon) in const [
            (ScreenshotAnnotationTool.select, '选择', Icons.near_me_outlined),
            (ScreenshotAnnotationTool.rectangle, '矩形', Icons.crop_square),
            (ScreenshotAnnotationTool.arrow, '箭头', Icons.north_east),
            (ScreenshotAnnotationTool.brush, '画笔', Icons.brush_outlined),
            (ScreenshotAnnotationTool.text, '文字', Icons.text_fields),
            (ScreenshotAnnotationTool.mosaic, '马赛克', Icons.grid_on_outlined),
          ])
            ChoiceChip(
              selected: _tool == tool,
              onSelected: _rendering
                  ? null
                  : (_) => setState(() {
                        _tool = tool;
                        _start = null;
                        _brushPoints = const [];
                        _draft = null;
                        _selected = null;
                        _movingOriginal = null;
                        _movePreview = null;
                        _resizeHandle = null;
                      }),
              avatar: Icon(icon, size: 18),
              label: Text(label),
            ),
          const SizedBox(width: 4),
          for (final color in screenshotAnnotationColors)
            Tooltip(
              message: '使用颜色 #${color.toRadixString(16).substring(2)}',
              child: InkWell(
                onTap: _rendering ? null : () => setState(() => _color = color),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == color
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: _color == color ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
              tooltip: '撤销',
              onPressed: !_rendering && _history.canUndo ? _undo : null,
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: '重做',
              onPressed: !_rendering && _history.canRedo ? _redo : null,
              icon: const Icon(Icons.redo)),
          IconButton(
              tooltip: '删除标注',
              onPressed:
                  !_rendering && _selected != null ? _deleteSelected : null,
              icon: const Icon(Icons.delete_outline)),
        ],
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

/// 在截图画布附近显示当前指针周围的放大区域，方便精确拖拽控制点和
/// 绘制细小标注。使用显示尺寸进行缩放，不会改变最终导出图片内容。
class _ScreenshotMagnifier extends StatelessWidget {
  const _ScreenshotMagnifier({
    required this.bytes,
    required this.displaySize,
    required this.center,
  });

  static const size = 116.0;
  static const zoom = 3.0;

  final Uint8List bytes;
  final Size displaySize;
  final Offset center;

  @override
  Widget build(BuildContext context) {
    final scaled = Size(displaySize.width * zoom, displaySize.height * zoom);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).colorScheme.onSurface, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(children: [
            Positioned(
              left: size / 2 - center.dx * zoom,
              top: size / 2 - center.dy * zoom,
              width: scaled.width,
              height: scaled.height,
              child:
                  Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
            ),
            const Positioned.fill(
                child: CustomPaint(painter: _MagnifierCrosshairPainter())),
          ]),
        ),
      ),
    );
  }
}

class _MagnifierCrosshairPainter extends CustomPainter {
  const _MagnifierCrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(center.dx - 10, center.dy),
        Offset(center.dx + 10, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - 10),
        Offset(center.dx, center.dy + 10), paint);
    canvas.drawCircle(center, 3, paint);
  }

  @override
  bool shouldRepaint(covariant _MagnifierCrosshairPainter oldDelegate) => false;
}

class ScreenshotAnnotationPainter extends CustomPainter {
  const ScreenshotAnnotationPainter({
    required this.annotations,
    required this.imageSize,
    this.draft,
    this.selected,
    this.movePreview,
  });

  final List<ScreenshotAnnotation> annotations;
  final ScreenshotAnnotation? draft;
  final ScreenshotAnnotation? selected;
  final ScreenshotAnnotation? movePreview;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / imageSize.width, size.height / imageSize.height);
    for (final annotation in annotations) {
      if (movePreview != null && identical(annotation, selected)) continue;
      _draw(canvas, annotation);
    }
    if (draft != null) _draw(canvas, draft!);
    if (movePreview != null) _draw(canvas, movePreview!);
    final highlighted = movePreview ?? selected;
    if (highlighted != null) {
      _drawSelection(canvas, highlighted, size.width / imageSize.width);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, ScreenshotAnnotation annotation) {
    paintScreenshotAnnotation(canvas, annotation, imageSize);
  }

  void _drawSelection(
      Canvas canvas, ScreenshotAnnotation annotation, double scale) {
    final bounds = screenshotAnnotationBounds(annotation, imageSize);
    final outside = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 / scale;
    final accent = Paint()
      ..color = const Color(0xff2563eb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale;
    canvas.drawRect(bounds, outside);
    canvas.drawRect(bounds, accent);
    final handleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final handle
        in screenshotAnnotationResizeHandles(annotation, imageSize).values) {
      canvas.drawCircle(handle, 4 / scale, handleFill);
      canvas.drawCircle(handle, 4 / scale, accent);
    }
  }

  @override
  bool shouldRepaint(covariant ScreenshotAnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations ||
      oldDelegate.draft != draft ||
      oldDelegate.selected != selected ||
      oldDelegate.movePreview != movePreview ||
      oldDelegate.imageSize != imageSize;
}
