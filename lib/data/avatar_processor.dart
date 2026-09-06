import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// 将头像裁剪为服务端要求的 256x256 WebP。
class AvatarProcessor {
  const AvatarProcessor();

  Uint8List process(
    Uint8List bytes, {
    double zoom = 1,
    double focusX = 0.5,
    double focusY = 0.5,
  }) {
    final source = image.decodeImage(bytes);
    if (source == null) throw const FormatException('无法读取头像图片');
    final scale = zoom.clamp(1, 3);
    final cropSize =
        (source.width < source.height ? source.width : source.height) / scale;
    final size =
        cropSize.round().clamp(1, source.width).clamp(1, source.height).toInt();
    final centerX = source.width * focusX.clamp(0, 1);
    final centerY = source.height * focusY.clamp(0, 1);
    final x =
        (centerX - size / 2).round().clamp(0, source.width - size).toInt();
    final y =
        (centerY - size / 2).round().clamp(0, source.height - size).toInt();
    final square = image.copyCrop(
      source,
      x: x,
      y: y,
      width: size,
      height: size,
    );
    final cropped = image.copyResize(square, width: 256, height: 256);
    final encoded = image.encodeWebP(cropped);
    return Uint8List.fromList(encoded);
  }
}
