import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as image;

enum ScreenshotAnnotationTool { rectangle, arrow, brush, text }

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

double screenshotAnnotationFontSize({
  required double displayWidth,
  required int imageWidth,
}) {
  if (displayWidth <= 0 || imageWidth <= 0) {
    throw ArgumentError('截图坐标系尺寸必须大于 0');
  }
  return math.max(16, 20 / (displayWidth / imageWidth));
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

class ScreenshotTextAnnotation extends ScreenshotAnnotation {
  const ScreenshotTextAnnotation({
    required this.position,
    required this.text,
    required this.fontSize,
    required super.color,
  }) : super(lineWidth: 0);

  final ScreenshotAnnotationPoint position;
  final String text;
  final double fontSize;
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

  FutureOr<Uint8List> render(
      Uint8List sourceBytes, List<ScreenshotAnnotation> annotations) {
    if (annotations.isEmpty) return sourceBytes;
    if (!annotations
        .any((annotation) => annotation is ScreenshotTextAnnotation)) {
      return _renderRasterAnnotations(sourceBytes, annotations);
    }
    return _renderTextAnnotations(sourceBytes, annotations);
  }

  Uint8List _renderRasterAnnotations(
      Uint8List sourceBytes, List<ScreenshotAnnotation> annotations) {
    image.Image? output;
    try {
      output = image.decodeImage(sourceBytes);
    } catch (_) {
      throw const FormatException('无法读取截图图片');
    }
    if (output == null) throw const FormatException('无法读取截图图片');
    for (final annotation in annotations) {
      final color = image.ColorRgba8(
        (annotation.color >> 16) & 0xff,
        (annotation.color >> 8) & 0xff,
        annotation.color & 0xff,
        (annotation.color >> 24) & 0xff,
      );
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
        _drawRasterArrow(output, arrow, color);
      } else if (annotation case ScreenshotBrushAnnotation brush) {
        if (brush.points.length == 1) {
          final point = brush.points.single;
          image.drawLine(output,
              x1: point.x.round(),
              y1: point.y.round(),
              x2: point.x.round(),
              y2: point.y.round(),
              color: color,
              thickness: annotation.lineWidth,
              antialias: true);
          continue;
        }
        for (var index = 1; index < brush.points.length; index++) {
          final start = brush.points[index - 1];
          final end = brush.points[index];
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
    }
    return Uint8List.fromList(image.encodePng(output));
  }

  void _drawRasterArrow(image.Image output,
      ScreenshotArrowAnnotation annotation, image.Color color) {
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

  Future<Uint8List> _renderTextAnnotations(
      Uint8List sourceBytes, List<ScreenshotAnnotation> annotations) async {
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? output;
    try {
      codec = await ui.instantiateImageCodec(sourceBytes);
      source = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final imageSize = Size(source.width.toDouble(), source.height.toDouble());
      canvas.drawImage(source, ui.Offset.zero, ui.Paint());
      for (final annotation in annotations) {
        paintScreenshotAnnotation(canvas, annotation, imageSize);
      }
      output =
          await recorder.endRecording().toImage(source.width, source.height);
      final encoded = await output.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw const FormatException('无法生成截图图片');
      return encoded.buffer
          .asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
    } catch (_) {
      throw const FormatException('无法读取截图图片');
    } finally {
      output?.dispose();
      source?.dispose();
      codec?.dispose();
    }
  }
}

void paintScreenshotAnnotation(
    ui.Canvas canvas, ScreenshotAnnotation annotation, Size imageSize) {
  final paint = ui.Paint()
    ..color = ui.Color(annotation.color)
    ..strokeWidth = annotation.lineWidth
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..style = ui.PaintingStyle.stroke;
  if (annotation case ScreenshotRectangleAnnotation rectangle) {
    canvas.drawRect(
        ui.Rect.fromPoints(ui.Offset(rectangle.start.x, rectangle.start.y),
            ui.Offset(rectangle.end.x, rectangle.end.y)),
        paint);
  } else if (annotation case ScreenshotArrowAnnotation arrow) {
    final start = ui.Offset(arrow.start.x, arrow.start.y);
    final end = ui.Offset(arrow.end.x, arrow.end.y);
    canvas.drawLine(start, end, paint);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final headLength = math.max(12.0, annotation.lineWidth * 4);
    final halfWidth = math.max(1.0, annotation.lineWidth * 1.5);
    final base = ui.Offset(end.dx - headLength * math.cos(angle),
        end.dy - headLength * math.sin(angle));
    final offset =
        ui.Offset(halfWidth * math.sin(angle), -halfWidth * math.cos(angle));
    canvas.drawPath(
        ui.Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(base.dx + offset.dx, base.dy + offset.dy)
          ..lineTo(base.dx - offset.dx, base.dy - offset.dy)
          ..close(),
        paint..style = ui.PaintingStyle.fill);
  } else if (annotation case ScreenshotBrushAnnotation brush) {
    if (brush.points.isEmpty) return;
    final path = ui.Path()..moveTo(brush.points.first.x, brush.points.first.y);
    for (final point in brush.points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(path, paint);
  } else if (annotation case ScreenshotTextAnnotation text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.text,
        style: TextStyle(
          color: ui.Color(text.color),
          fontSize: text.fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: math.max(1, imageSize.width - text.position.x));
    painter.paint(canvas, ui.Offset(text.position.x, text.position.y));
    painter.dispose();
  }
}
