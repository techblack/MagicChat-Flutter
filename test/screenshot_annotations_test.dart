import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/domain/screenshot_annotations.dart';

void main() {
  test('标注历史支持撤销重做且新操作清空重做栈', () {
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(2, 2),
      end: ScreenshotAnnotationPoint(20, 15),
      color: 0xffef4444,
      lineWidth: 2,
    );
    const arrow = ScreenshotArrowAnnotation(
      start: ScreenshotAnnotationPoint(5, 20),
      end: ScreenshotAnnotationPoint(25, 20),
      color: 0xff2563eb,
      lineWidth: 3,
    );

    var history = const ScreenshotAnnotationHistory().commit(rectangle);
    expect(history.present, [rectangle]);
    expect(history.canUndo, isTrue);
    history = history.undo();
    expect(history.present, isEmpty);
    expect(history.canRedo, isTrue);
    history = history.redo();
    expect(history.present, [rectangle]);
    history = history.undo().commit(arrow);
    expect(history.present, [arrow]);
    expect(history.canRedo, isFalse);
  });

  test('显示坐标按高 DPI 比例映射并限制到原图边界', () {
    final center = screenshotImagePointFromDisplay(
      x: 240,
      y: 135,
      displayWidth: 960,
      displayHeight: 540,
      imageWidth: 3840,
      imageHeight: 2160,
    );
    final bounded = screenshotImagePointFromDisplay(
      x: 1200,
      y: -10,
      displayWidth: 960,
      displayHeight: 540,
      imageWidth: 3840,
      imageHeight: 2160,
    );

    expect(center.x, 960);
    expect(center.y, 540);
    expect(bounded.x, 3840);
    expect(bounded.y, 0);
    expect(
        screenshotAnnotationLineWidth(displayWidth: 960, imageWidth: 3840), 12);
    expect(
        screenshotAnnotationFontSize(displayWidth: 960, imageWidth: 3840), 80);
  });

  test('矩形箭头画笔和中文文字烘焙进 PNG，空标注保留原字节', () async {
    final source = image.Image(width: 64, height: 48, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(255, 255, 255, 255));
    final sourceBytes = Uint8List.fromList(image.encodePng(source));
    const renderer = ScreenshotAnnotationRenderer();
    final empty = await renderer.render(sourceBytes, const []);
    final rendered = await renderer.render(sourceBytes, [
      const ScreenshotRectangleAnnotation(
        start: ScreenshotAnnotationPoint(2, 2),
        end: ScreenshotAnnotationPoint(20, 15),
        color: 0xffff0000,
        lineWidth: 2,
      ),
      const ScreenshotArrowAnnotation(
        start: ScreenshotAnnotationPoint(5, 30),
        end: ScreenshotAnnotationPoint(30, 30),
        color: 0xff0000ff,
        lineWidth: 2,
      ),
      ScreenshotBrushAnnotation(
        points: const [
          ScreenshotAnnotationPoint(48, 4),
          ScreenshotAnnotationPoint(48, 18),
          ScreenshotAnnotationPoint(58, 18),
        ],
        color: 0xff00ff00,
        lineWidth: 3,
      ),
      const ScreenshotTextAnnotation(
        position: ScreenshotAnnotationPoint(6, 33),
        text: '重点',
        fontSize: 12,
        color: 0xffef4444,
      ),
    ]);
    final output = image.decodePng(rendered)!;

    expect(identical(empty, sourceBytes), isTrue);
    expect(output.width, 64);
    expect(output.height, 48);
    _expectRgb(output.getPixel(2, 2), 255, 0, 0);
    _expectRgb(output.getPixel(15, 30), 0, 0, 255);
    _expectRgb(output.getPixel(48, 10), 0, 255, 0);
    _expectRgb(output.getPixel(40, 40), 255, 255, 255);
  });

  test('马赛克只像素化选中区域并保留边框', () async {
    final source = image.Image(width: 48, height: 32, numChannels: 4);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, x * 5, y * 7, (x + y) * 3, 255);
      }
    }
    final sourceBytes = Uint8List.fromList(image.encodePng(source));
    final rendered = await const ScreenshotAnnotationRenderer().render(
      sourceBytes,
      const [
        ScreenshotMosaicAnnotation(
          start: ScreenshotAnnotationPoint(10, 8),
          end: ScreenshotAnnotationPoint(38, 26),
          color: 0xffff0000,
          lineWidth: 2,
        ),
      ],
    );
    final output = image.decodePng(rendered)!;

    _expectRgb(output.getPixel(4, 4), 20, 28, 24);
    _expectRgb(output.getPixel(10, 8), 255, 0, 0);
    final mosaicColors = <String>{
      for (var y = 10; y < 24; y++)
        for (var x = 12; x < 36; x++) _rgbKey(output.getPixel(x, y)),
    };
    expect(mosaicColors.length, lessThan(30));
    expect(_rgbKey(output.getPixel(15, 13)),
        isNot(_rgbKey(source.getPixel(15, 13))));
  });

  test('无效图片不生成标注结果', () {
    expect(
      () => const ScreenshotAnnotationRenderer()
          .render(Uint8List.fromList([1, 2, 3]), [
        const ScreenshotRectangleAnnotation(
          start: ScreenshotAnnotationPoint(0, 0),
          end: ScreenshotAnnotationPoint(2, 2),
          color: 0xffff0000,
          lineWidth: 2,
        ),
      ]),
      throwsFormatException,
    );
  });
}

void _expectRgb(image.Pixel pixel, int red, int green, int blue) {
  expect(pixel.r.toInt(), red);
  expect(pixel.g.toInt(), green);
  expect(pixel.b.toInt(), blue);
}

String _rgbKey(image.Pixel pixel) =>
    '${pixel.r.toInt()}:${pixel.g.toInt()}:${pixel.b.toInt()}';
