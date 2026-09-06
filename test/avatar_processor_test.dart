import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/avatar_processor.dart';

void main() {
  test('头像统一裁剪为 256x256 WebP', () {
    final source = image.Image(width: 640, height: 320);
    final input = Uint8List.fromList(image.encodePng(source));
    final output = const AvatarProcessor().process(input);
    final decoded = image.decodeWebP(output);
    expect(decoded, isNotNull);
    expect(decoded!.width, 256);
    expect(decoded.height, 256);
  });

  test('头像缩放和焦点决定实际裁剪区域', () {
    final source = image.Image(width: 400, height: 200);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x < 200 ? 255 : 0, 0, x < 200 ? 0 : 255);
      }
    }
    final input = Uint8List.fromList(image.encodePng(source));

    final left = image.decodeWebP(const AvatarProcessor()
        .process(input, zoom: 2, focusX: 0.25, focusY: 0.5))!;
    final right = image.decodeWebP(const AvatarProcessor()
        .process(input, zoom: 2, focusX: 0.75, focusY: 0.5))!;

    final leftPixel = left.getPixel(128, 128);
    final rightPixel = right.getPixel(128, 128);
    expect(leftPixel.r, greaterThan(leftPixel.b));
    expect(rightPixel.b, greaterThan(rightPixel.r));
  });
}
