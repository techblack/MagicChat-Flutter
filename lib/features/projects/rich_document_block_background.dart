import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/rich_document_format.dart';

class RichDocumentBlockBackground extends StatelessWidget {
  const RichDocumentBlockBackground({
    required this.color,
    required this.child,
    super.key,
  });

  final Color color;
  final Widget child;
  Color get foregroundColor => richDocumentBlockForegroundColor(color);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '带背景的内容块',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foregroundColor),
          child: IconTheme.merge(
            data: IconThemeData(color: foregroundColor),
            child: child,
          ),
        ),
      ),
    );
  }
}

Color richDocumentBlockForegroundColor(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

/// 将协作 schema 中的 OKLCH 色值转换为 Flutter 使用的 sRGB。
Color? richDocumentBlockBackgroundDisplayColor(Object? value) {
  final normalized = normalizeRichDocumentBlockBackground(value);
  if (normalized == null) return null;
  final match = RegExp(r'^oklch\(([0-9.]+)% ([0-9.]+) ([0-9.]+)\)$')
      .firstMatch(normalized);
  if (match == null) return null;
  final lightness = double.parse(match.group(1)!) / 100;
  final chroma = double.parse(match.group(2)!);
  final hue = double.parse(match.group(3)!) * math.pi / 180;
  final a = chroma * math.cos(hue);
  final b = chroma * math.sin(hue);
  final lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final sRoot = lightness - 0.0894841775 * a - 1.2914855480 * b;
  final l = lRoot * lRoot * lRoot;
  final m = mRoot * mRoot * mRoot;
  final s = sRoot * sRoot * sRoot;
  return Color.fromARGB(
      255,
      (_linearSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s) *
              255)
          .round(),
      (_linearSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s) *
              255)
          .round(),
      (_linearSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s) *
              255)
          .round());
}

double _linearSrgb(double value) => (value <= 0.0031308
        ? 12.92 * value
        : 1.055 * math.pow(value, 1 / 2.4) - 0.055)
    .clamp(0, 1)
    .toDouble();
