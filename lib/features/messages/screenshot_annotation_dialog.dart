import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:image/image.dart' as image;

import '../../data/desktop_screenshot.dart';
import '../../domain/screenshot_annotations.dart';

const screenshotAnnotationColors = <int>[
  0xffef4444,
  0xfff59e0b,
  0xff22c55e,
  0xff2563eb,
  0xffffffff,
];

Future<CapturedScreenshot?> showScreenshotAnnotationDialog(
        BuildContext context, CapturedScreenshot screenshot) =>
    showDialog<CapturedScreenshot>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScreenshotAnnotationDialog(screenshot: screenshot),
    );

class ScreenshotAnnotationDialog extends StatefulWidget {
  const ScreenshotAnnotationDialog({required this.screenshot, super.key});

  final CapturedScreenshot screenshot;

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
  ScreenshotAnnotationPoint? _start;
  List<ScreenshotAnnotationPoint> _brushPoints = const [];
  final FocusNode _keyboardFocusNode = FocusNode();
  int _color = screenshotAnnotationColors.first;
  bool _rendering = false;
  String _error = '';
  late final int _imageWidth;
  late final int _imageHeight;

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
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _undo() => setState(() {
        _history = _history.undo();
        _draft = null;
        _selected = null;
      });

  void _redo() => setState(() {
        _history = _history.redo();
        _draft = null;
        _selected = null;
      });

  void _startDrawing(DragStartDetails details, Size displaySize) {
    if (_rendering ||
        _tool == ScreenshotAnnotationTool.select ||
        _tool == ScreenshotAnnotationTool.text) {
      return;
    }
    final point = _imagePoint(details.localPosition, displaySize);
    setState(() {
      _start = point;
      _brushPoints = [point];
      _draft = null;
      _error = '';
    });
  }

  void _updateDrawing(DragUpdateDetails details, Size displaySize) {
    final start = _start;
    if (start == null || _rendering) return;
    final point = _imagePoint(details.localPosition, displaySize);
    final lineWidth = screenshotAnnotationLineWidth(
        displayWidth: displaySize.width, imageWidth: _imageWidth);
    setState(() {
      switch (_tool) {
        case ScreenshotAnnotationTool.select:
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
    final draft = _draft;
    setState(() {
      if (draft != null && _isVisible(draft)) {
        _history = _history.commit(draft);
      }
      _selected = null;
      _start = null;
      _brushPoints = const [];
      _draft = null;
    });
  }

  void _cancelDrawing() => setState(() {
        _start = null;
        _brushPoints = const [];
        _draft = null;
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
  }

  void _handleCanvasTap(TapUpDetails details, Size displaySize) {
    if (_rendering) return;
    if (_tool == ScreenshotAnnotationTool.text) {
      _addText(details, displaySize);
      return;
    }
    if (_tool != ScreenshotAnnotationTool.select) return;
    final imagePoint = _imagePoint(details.localPosition, displaySize);
    final tolerance = 8 * _imageWidth / displaySize.width;
    setState(() {
      _selected = hitTestScreenshotAnnotation(
        annotations: _history.present,
        point: imagePoint,
        imageSize: Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
        tolerance: tolerance,
      );
    });
    _keyboardFocusNode.requestFocus();
  }

  void _deleteSelected() {
    final selected = _selected;
    if (_rendering || selected == null) return;
    final next = _history.remove(selected);
    if (identical(next, _history)) return;
    setState(() {
      _history = next;
      _selected = null;
      _draft = null;
    });
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
      final rendered = const ScreenshotAnnotationRenderer()
          .render(widget.screenshot.bytes, _history.present);
      final bytes = rendered is Future<Uint8List> ? await rendered : rendered;
      if (bytes.length > desktopScreenshotMaxImageBytes) {
        throw const DesktopScreenshotException(
          DesktopScreenshotErrorCode.imageTooLarge,
          '截图标注结果超过 32MiB，请减少标注或缩小截图区域',
        );
      }
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
                  TextButton(
                      onPressed:
                          _rendering ? null : () => Navigator.pop(context),
                      child: const Text('取消')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _rendering ? null : _finish,
                    icon: _rendering
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
        return Stack(children: [
          Positioned.fromRect(
            rect: rect,
            child: ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(widget.screenshot.bytes,
                    fit: BoxFit.fill, gaplessPlayback: true),
                GestureDetector(
                  key: const ValueKey('screenshot-annotation-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) => _startDrawing(details, displaySize),
                  onPanUpdate: (details) =>
                      _updateDrawing(details, displaySize),
                  onPanEnd: _finishDrawing,
                  onPanCancel: _cancelDrawing,
                  onTapUp: (details) => _handleCanvasTap(details, displaySize),
                  child: CustomPaint(
                    painter: ScreenshotAnnotationPainter(
                      annotations: _history.present,
                      draft: _draft,
                      selected: _selected,
                      imageSize:
                          Size(_imageWidth.toDouble(), _imageHeight.toDouble()),
                    ),
                  ),
                ),
              ]),
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

class ScreenshotAnnotationPainter extends CustomPainter {
  const ScreenshotAnnotationPainter({
    required this.annotations,
    required this.imageSize,
    this.draft,
    this.selected,
  });

  final List<ScreenshotAnnotation> annotations;
  final ScreenshotAnnotation? draft;
  final ScreenshotAnnotation? selected;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / imageSize.width, size.height / imageSize.height);
    for (final annotation in [
      ...annotations,
      if (draft != null) draft!,
    ]) {
      _draw(canvas, annotation);
    }
    if (selected != null) {
      _drawSelection(canvas, selected!, size.width / imageSize.width);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, ScreenshotAnnotation annotation) {
    paintScreenshotAnnotation(canvas, annotation, imageSize);
  }

  void _drawSelection(
      Canvas canvas, ScreenshotAnnotation annotation, double scale) {
    final bounds = screenshotAnnotationBounds(annotation, imageSize)
        .inflate(math.max(annotation.lineWidth, 4 / scale));
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
    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      canvas.drawCircle(corner, 4 / scale, handleFill);
      canvas.drawCircle(corner, 4 / scale, accent);
    }
  }

  @override
  bool shouldRepaint(covariant ScreenshotAnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations ||
      oldDelegate.draft != draft ||
      oldDelegate.selected != selected ||
      oldDelegate.imageSize != imageSize;
}
