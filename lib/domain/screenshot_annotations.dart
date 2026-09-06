import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

enum ScreenshotAnnotationTool { rectangle, arrow, brush }

class ScreenshotAnnotationPoint {
  const ScreenshotAnnotationPoint(this.x, this.y);

  final double x;
  final double y;
}

ScreenshotAnnotationPoint screenshotImagePointFromDisplay({
  required double x,
  required double y,
  required double displayWidth,
  required double displayHeight,
  required int imageWidth,
  required int imageHeight,
}) {
  if (displayWidth <= 0 ||
      displayHeight <= 0 ||
      imageWidth <= 0 ||
      imageHeight <= 0) {
    throw ArgumentError('截图坐标系尺寸必须大于 0');
  }
  return ScreenshotAnnotationPoint(
    (x * imageWidth / displayWidth).clamp(0, imageWidth.toDouble()),
    (y * imageHeight / displayHeight).clamp(0, imageHeight.toDouble()),
  );
}

double screenshotAnnotationLineWidth({
  required double displayWidth,
  required int imageWidth,
}) {
  if (displayWidth <= 0 || imageWidth <= 0) {
    throw ArgumentError('截图坐标系尺寸必须大于 0');
  }
  return math.max(2, 3 / (displayWidth / imageWidth));
}

sealed class ScreenshotAnnotation {
  const ScreenshotAnnotation({required this.color, required this.lineWidth});

  final int color;
  final double lineWidth;
}

class ScreenshotRectangleAnnotation extends ScreenshotAnnotation {
  const ScreenshotRectangleAnnotation({
    required this.start,
    required this.end,
    required super.color,
    required super.lineWidth,
  });

  final ScreenshotAnnotationPoint start;
  final ScreenshotAnnotationPoint end;
}

class ScreenshotArrowAnnotation extends ScreenshotAnnotation {
  const ScreenshotArrowAnnotation({
    required this.start,
    required this.end,
    required super.color,
    required super.lineWidth,
  });

  final ScreenshotAnnotationPoint start;
  final ScreenshotAnnotationPoint end;
}

class ScreenshotBrushAnnotation extends ScreenshotAnnotation {
  ScreenshotBrushAnnotation({
    required List<ScreenshotAnnotationPoint> points,
    required super.color,
    required super.lineWidth,
  }) : points = List.unmodifiable(points);

  final List<ScreenshotAnnotationPoint> points;
}

class ScreenshotAnnotationHistory {
  const ScreenshotAnnotationHistory({
    this.past = const [],
    this.present = const [],
    this.future = const [],
  });

  final List<List<ScreenshotAnnotation>> past;
  final List<ScreenshotAnnotation> present;
  final List<List<ScreenshotAnnotation>> future;

  bool get canUndo => past.isNotEmpty;
  bool get canRedo => future.isNotEmpty;

  ScreenshotAnnotationHistory commit(ScreenshotAnnotation annotation) =>
      ScreenshotAnnotationHistory(
        past: [...past, present],
        present: [...present, annotation],
      );

  ScreenshotAnnotationHistory undo() {
    if (!canUndo) return this;
    return ScreenshotAnnotationHistory(
      past: past.sublist(0, past.length - 1),
      present: past.last,
      future: [present, ...future],
    );
  }

  ScreenshotAnnotationHistory redo() {
    if (!canRedo) return this;
    return ScreenshotAnnotationHistory(
      past: [...past, present],
      present: future.first,
      future: future.sublist(1),
    );
  }
}

class ScreenshotAnnotationRenderer {
  const ScreenshotAnnotationRenderer();

  Uint8List render(
      Uint8List sourceBytes, List<ScreenshotAnnotation> annotations) {
    if (annotations.isEmpty) return sourceBytes;
    image.Image? output;
    try {
      output = image.decodeImage(sourceBytes);
    } catch (_) {
      throw const FormatException('无法读取截图图片');
    }
    if (output == null) throw const FormatException('无法读取截图图片');
    for (final annotation in annotations) {
      final color = _imageColor(annotation.color);
      if (annotation case ScreenshotRectangleAnnotation rectangle) {
        image.drawRect(output,
            x1: rectangle.start.x.round(),
            y1: rectangle.start.y.round(),
            x2: rectangle.end.x.round(),
            y2: rectangle.end.y.round(),
            color: color,
            thickness: rectangle.lineWidth,
            blend: image.BlendMode.alpha);
      } else if (annotation case ScreenshotArrowAnnotation arrow) {
        _drawArrow(output, arrow, color);
      } else if (annotation case ScreenshotBrushAnnotation brush) {
        _drawBrush(output, brush, color);
      }
    }
    return Uint8List.fromList(image.encodePng(output));
  }

  void _drawBrush(image.Image output, ScreenshotBrushAnnotation annotation,
      image.Color color) {
    if (annotation.points.isEmpty) return;
    if (annotation.points.length == 1) {
      final point = annotation.points.single;
      image.drawLine(output,
          x1: point.x.round(),
          y1: point.y.round(),
          x2: point.x.round(),
          y2: point.y.round(),
          color: color,
          thickness: annotation.lineWidth,
          antialias: true);
      return;
    }
    for (var index = 1; index < annotation.points.length; index++) {
      final start = annotation.points[index - 1];
      final end = annotation.points[index];
      image.drawLine(output,
          x1: start.x.round(),
          y1: start.y.round(),
          x2: end.x.round(),
          y2: end.y.round(),
          color: color,
          thickness: annotation.lineWidth,
          antialias: true);
    }
  }

  void _drawArrow(image.Image output, ScreenshotArrowAnnotation annotation,
      image.Color color) {
    final start = annotation.start;
    final end = annotation.end;
    image.drawLine(output,
        x1: start.x.round(),
        y1: start.y.round(),
        x2: end.x.round(),
        y2: end.y.round(),
        color: color,
        thickness: annotation.lineWidth,
        antialias: true);
    final angle = math.atan2(end.y - start.y, end.x - start.x);
    final headLength = math.max(12.0, annotation.lineWidth * 4);
    final halfWidth = math.max(1.0, annotation.lineWidth * 1.5);
    final baseX = end.x - headLength * math.cos(angle);
    final baseY = end.y - headLength * math.sin(angle);
    final offsetX = halfWidth * math.sin(angle);
    final offsetY = halfWidth * math.cos(angle);
    image.fillPolygon(output, color: color, vertices: [
      image.Point(end.x, end.y),
      image.Point(baseX - offsetX, baseY + offsetY),
      image.Point(baseX + offsetX, baseY - offsetY),
    ]);
  }

  image.Color _imageColor(int value) => image.ColorRgba8(
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
        (value >> 24) & 0xff,
      );
}
