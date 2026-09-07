import 'dart:typed_data';
import 'dart:ui';

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

  test('选择命中最上层矩形、箭头、文字和马赛克，空白不命中', () {
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(10, 10),
      end: ScreenshotAnnotationPoint(80, 60),
      color: 0xffef4444,
      lineWidth: 3,
    );
    const arrow = ScreenshotArrowAnnotation(
      start: ScreenshotAnnotationPoint(100, 30),
      end: ScreenshotAnnotationPoint(180, 30),
      color: 0xff2563eb,
      lineWidth: 3,
    );
    const text = ScreenshotTextAnnotation(
      position: ScreenshotAnnotationPoint(210, 20),
      text: '重点',
      fontSize: 20,
      color: 0xff22c55e,
    );
    const mosaic = ScreenshotMosaicAnnotation(
      start: ScreenshotAnnotationPoint(30, 20),
      end: ScreenshotAnnotationPoint(70, 50),
      color: 0xfff59e0b,
      lineWidth: 3,
    );
    const annotations = [rectangle, arrow, text, mosaic];
    const imageSize = Size(320, 180);

    expect(
      hitTestScreenshotAnnotation(
        annotations: annotations,
        point: const ScreenshotAnnotationPoint(40, 30),
        imageSize: imageSize,
      ),
      same(mosaic),
    );
    expect(
      hitTestScreenshotAnnotation(
        annotations: annotations,
        point: const ScreenshotAnnotationPoint(120, 33),
        imageSize: imageSize,
      ),
      same(arrow),
    );
    expect(
      hitTestScreenshotAnnotation(
        annotations: annotations,
        point: const ScreenshotAnnotationPoint(215, 25),
        imageSize: imageSize,
      ),
      same(text),
    );
    expect(
      hitTestScreenshotAnnotation(
        annotations: const [rectangle],
        point: const ScreenshotAnnotationPoint(40, 30),
        imageSize: imageSize,
      ),
      same(rectangle),
    );
    expect(
      hitTestScreenshotAnnotation(
        annotations: annotations,
        point: const ScreenshotAnnotationPoint(300, 160),
        imageSize: imageSize,
      ),
      isNull,
    );
  });

  test('删除指定标注进入撤销重做历史', () {
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(2, 2),
      end: ScreenshotAnnotationPoint(20, 15),
      color: 0xffef4444,
      lineWidth: 2,
    );
    const mosaic = ScreenshotMosaicAnnotation(
      start: ScreenshotAnnotationPoint(4, 4),
      end: ScreenshotAnnotationPoint(12, 10),
      color: 0xff2563eb,
      lineWidth: 2,
    );
    final initial =
        const ScreenshotAnnotationHistory().commit(rectangle).commit(mosaic);

    final removed = initial.remove(rectangle);
    expect(removed.present, [mosaic]);
    expect(removed.undo().present, [rectangle, mosaic]);
    expect(removed.undo().redo().present, [mosaic]);
    expect(identical(removed.remove(rectangle), removed), isTrue);
  });

  test('矩形箭头画笔文字和马赛克统一按原图坐标平移', () {
    const imageSize = Size(320, 180);
    const delta = Offset(15, 12);
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(10, 20),
      end: ScreenshotAnnotationPoint(50, 60),
      color: 0xffef4444,
      lineWidth: 3,
    );
    const arrow = ScreenshotArrowAnnotation(
      start: ScreenshotAnnotationPoint(70, 30),
      end: ScreenshotAnnotationPoint(120, 50),
      color: 0xff2563eb,
      lineWidth: 4,
    );
    final brush = ScreenshotBrushAnnotation(
      points: const [
        ScreenshotAnnotationPoint(130, 40),
        ScreenshotAnnotationPoint(150, 55),
      ],
      color: 0xff22c55e,
      lineWidth: 5,
    );
    const text = ScreenshotTextAnnotation(
      position: ScreenshotAnnotationPoint(180, 50),
      text: '重点',
      fontSize: 20,
      color: 0xfff59e0b,
    );
    const mosaic = ScreenshotMosaicAnnotation(
      start: ScreenshotAnnotationPoint(230, 70),
      end: ScreenshotAnnotationPoint(270, 110),
      color: 0xffef4444,
      lineWidth: 3,
    );

    final movedRectangle = translateScreenshotAnnotation(
        annotation: rectangle,
        delta: delta,
        imageSize: imageSize) as ScreenshotRectangleAnnotation;
    final movedArrow = translateScreenshotAnnotation(
        annotation: arrow,
        delta: delta,
        imageSize: imageSize) as ScreenshotArrowAnnotation;
    final movedBrush = translateScreenshotAnnotation(
        annotation: brush,
        delta: delta,
        imageSize: imageSize) as ScreenshotBrushAnnotation;
    final movedText = translateScreenshotAnnotation(
        annotation: text,
        delta: delta,
        imageSize: imageSize) as ScreenshotTextAnnotation;
    final movedMosaic = translateScreenshotAnnotation(
        annotation: mosaic,
        delta: delta,
        imageSize: imageSize) as ScreenshotMosaicAnnotation;

    expect((movedRectangle.start.x, movedRectangle.start.y), (25, 32));
    expect((movedRectangle.end.x, movedRectangle.end.y), (65, 72));
    expect((movedArrow.start.x, movedArrow.start.y), (85, 42));
    expect((movedArrow.end.x, movedArrow.end.y), (135, 62));
    expect((movedBrush.points.first.x, movedBrush.points.first.y), (145, 52));
    expect((movedBrush.points.last.x, movedBrush.points.last.y), (165, 67));
    expect((movedText.position.x, movedText.position.y), (195, 62));
    expect((movedMosaic.start.x, movedMosaic.start.y), (245, 82));
    expect((movedMosaic.end.x, movedMosaic.end.y), (285, 122));
  });

  test('各类标注平移时整体限制在图像边界', () {
    const imageSize = Size(320, 180);
    final annotations = <ScreenshotAnnotation>[
      const ScreenshotRectangleAnnotation(
        start: ScreenshotAnnotationPoint(10, 20),
        end: ScreenshotAnnotationPoint(50, 60),
        color: 0xffef4444,
        lineWidth: 3,
      ),
      const ScreenshotArrowAnnotation(
        start: ScreenshotAnnotationPoint(70, 30),
        end: ScreenshotAnnotationPoint(120, 50),
        color: 0xff2563eb,
        lineWidth: 4,
      ),
      ScreenshotBrushAnnotation(
        points: const [
          ScreenshotAnnotationPoint(130, 40),
          ScreenshotAnnotationPoint(150, 55),
        ],
        color: 0xff22c55e,
        lineWidth: 5,
      ),
      const ScreenshotTextAnnotation(
        position: ScreenshotAnnotationPoint(180, 50),
        text: '重点',
        fontSize: 20,
        color: 0xfff59e0b,
      ),
      const ScreenshotMosaicAnnotation(
        start: ScreenshotAnnotationPoint(230, 70),
        end: ScreenshotAnnotationPoint(270, 110),
        color: 0xffef4444,
        lineWidth: 3,
      ),
    ];

    for (final annotation in annotations) {
      final bottomRight = translateScreenshotAnnotation(
        annotation: annotation,
        delta: const Offset(1000, 1000),
        imageSize: imageSize,
      );
      final topLeft = translateScreenshotAnnotation(
        annotation: bottomRight,
        delta: const Offset(-1000, -1000),
        imageSize: imageSize,
      );
      final bottomRightBounds =
          screenshotAnnotationBounds(bottomRight, imageSize);
      final topLeftBounds = screenshotAnnotationBounds(topLeft, imageSize);
      expect(bottomRightBounds.right, lessThanOrEqualTo(imageSize.width));
      expect(bottomRightBounds.bottom, lessThanOrEqualTo(imageSize.height));
      expect(topLeftBounds.left, greaterThanOrEqualTo(0));
      expect(topLeftBounds.top, greaterThanOrEqualTo(0));
    }
  });

  test('一次标注替换只产生一个撤销历史提交', () {
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(10, 20),
      end: ScreenshotAnnotationPoint(50, 60),
      color: 0xffef4444,
      lineWidth: 3,
    );
    final initial = const ScreenshotAnnotationHistory().commit(rectangle);
    final moved = translateScreenshotAnnotation(
      annotation: rectangle,
      delta: const Offset(20, 10),
      imageSize: const Size(320, 180),
    );

    final replaced = initial.replace(rectangle, moved);

    expect(replaced.past, hasLength(initial.past.length + 1));
    expect(replaced.present.single, same(moved));
    expect(replaced.undo().present.single, same(rectangle));
    expect(replaced.undo().redo().present.single, same(moved));
  });

  test('不同标注只暴露实际可操作的缩放控制点', () {
    const imageSize = Size(320, 180);
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(10, 20),
      end: ScreenshotAnnotationPoint(50, 60),
      color: 0xffef4444,
      lineWidth: 3,
    );
    const arrow = ScreenshotArrowAnnotation(
      start: ScreenshotAnnotationPoint(70, 30),
      end: ScreenshotAnnotationPoint(120, 50),
      color: 0xff2563eb,
      lineWidth: 4,
    );
    const text = ScreenshotTextAnnotation(
      position: ScreenshotAnnotationPoint(180, 50),
      text: '重点',
      fontSize: 20,
      color: 0xfff59e0b,
    );

    expect(screenshotAnnotationResizeHandles(rectangle, imageSize).keys,
        containsAll(ScreenshotAnnotationResizeHandle.values.take(4)));
    expect(screenshotAnnotationResizeHandles(arrow, imageSize), {
      ScreenshotAnnotationResizeHandle.arrowEnd: const Offset(120, 50),
    });
    expect(screenshotAnnotationResizeHandles(text, imageSize).keys,
        [ScreenshotAnnotationResizeHandle.bottomRight]);
    expect(
      hitTestScreenshotAnnotationResizeHandle(
        annotation: arrow,
        point: const ScreenshotAnnotationPoint(123, 52),
        imageSize: imageSize,
      ),
      ScreenshotAnnotationResizeHandle.arrowEnd,
    );
  });

  test('矩形和马赛克四角缩放固定对角并限制边界', () {
    const imageSize = Size(200, 140);
    const rectangle = ScreenshotRectangleAnnotation(
      start: ScreenshotAnnotationPoint(40, 30),
      end: ScreenshotAnnotationPoint(120, 90),
      color: 0xffef4444,
      lineWidth: 3,
    );
    const mosaic = ScreenshotMosaicAnnotation(
      start: ScreenshotAnnotationPoint(40, 30),
      end: ScreenshotAnnotationPoint(120, 90),
      color: 0xff2563eb,
      lineWidth: 3,
    );
    const targets = {
      ScreenshotAnnotationResizeHandle.topLeft:
          ScreenshotAnnotationPoint(-100, -100),
      ScreenshotAnnotationResizeHandle.topRight:
          ScreenshotAnnotationPoint(300, -100),
      ScreenshotAnnotationResizeHandle.bottomLeft:
          ScreenshotAnnotationPoint(-100, 300),
      ScreenshotAnnotationResizeHandle.bottomRight:
          ScreenshotAnnotationPoint(300, 300),
    };
    const fixedCorners = {
      ScreenshotAnnotationResizeHandle.topLeft: Offset(120, 90),
      ScreenshotAnnotationResizeHandle.topRight: Offset(40, 90),
      ScreenshotAnnotationResizeHandle.bottomLeft: Offset(120, 30),
      ScreenshotAnnotationResizeHandle.bottomRight: Offset(40, 30),
    };

    for (final annotation in [rectangle, mosaic]) {
      for (final handle in targets.keys) {
        final resized = resizeScreenshotAnnotation(
          annotation: annotation,
          handle: handle,
          point: targets[handle]!,
          imageSize: imageSize,
        );
        final bounds = screenshotAnnotationBounds(resized, imageSize);
        final fixed = switch (handle) {
          ScreenshotAnnotationResizeHandle.topLeft => bounds.bottomRight,
          ScreenshotAnnotationResizeHandle.topRight => bounds.bottomLeft,
          ScreenshotAnnotationResizeHandle.bottomLeft => bounds.topRight,
          ScreenshotAnnotationResizeHandle.bottomRight => bounds.topLeft,
          ScreenshotAnnotationResizeHandle.arrowEnd => Offset.zero,
        };
        expect(fixed, fixedCorners[handle]);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(imageSize.width));
        expect(bounds.bottom, lessThanOrEqualTo(imageSize.height));
      }
    }
  });

  test('箭头终点和文字字号缩放遵守最小值与图像边界', () {
    const arrow = ScreenshotArrowAnnotation(
      start: ScreenshotAnnotationPoint(40, 40),
      end: ScreenshotAnnotationPoint(100, 60),
      color: 0xff2563eb,
      lineWidth: 4,
    );
    final extended = resizeScreenshotAnnotation(
      annotation: arrow,
      handle: ScreenshotAnnotationResizeHandle.arrowEnd,
      point: const ScreenshotAnnotationPoint(1000, 1000),
      imageSize: const Size(200, 140),
    ) as ScreenshotArrowAnnotation;
    final collapsed = resizeScreenshotAnnotation(
      annotation: arrow,
      handle: ScreenshotAnnotationResizeHandle.arrowEnd,
      point: arrow.start,
      imageSize: const Size(200, 140),
    ) as ScreenshotArrowAnnotation;

    expect((extended.end.x, extended.end.y), (200, 140));
    expect(
        (Offset(collapsed.end.x, collapsed.end.y) -
                Offset(arrow.start.x, arrow.start.y))
            .distance,
        closeTo(screenshotAnnotationMinExtent, 0.000001));

    const text = ScreenshotTextAnnotation(
      position: ScreenshotAnnotationPoint(20, 20),
      text: '重点文字',
      fontSize: 20,
      color: 0xffef4444,
    );
    const imageSize = Size(300, 200);
    final bounds = screenshotAnnotationBounds(text, imageSize);
    final grown = resizeScreenshotAnnotation(
      annotation: text,
      handle: ScreenshotAnnotationResizeHandle.bottomRight,
      point: ScreenshotAnnotationPoint(
        bounds.left + bounds.width * 3,
        bounds.top + bounds.height * 3,
      ),
      imageSize: imageSize,
    ) as ScreenshotTextAnnotation;
    final shrunk = resizeScreenshotAnnotation(
      annotation: text,
      handle: ScreenshotAnnotationResizeHandle.bottomRight,
      point: text.position,
      imageSize: imageSize,
    ) as ScreenshotTextAnnotation;

    expect(grown.fontSize, greaterThan(text.fontSize));
    expect(grown.fontSize, lessThanOrEqualTo(screenshotAnnotationMaxFontSize));
    expect(screenshotAnnotationBounds(grown, imageSize).right,
        lessThanOrEqualTo(imageSize.width));
    expect(screenshotAnnotationBounds(grown, imageSize).bottom,
        lessThanOrEqualTo(imageSize.height));
    expect(shrunk.fontSize, screenshotAnnotationMinFontSize);
  });

  test('画笔按包围盒等比缩放并限制在图像边界', () {
    final brush = ScreenshotBrushAnnotation(
      points: const [
        ScreenshotAnnotationPoint(20, 20),
        ScreenshotAnnotationPoint(40, 30),
        ScreenshotAnnotationPoint(60, 40),
      ],
      color: 0xff22c55e,
      lineWidth: 3,
    );
    const imageSize = Size(200, 140);
    final doubled = resizeScreenshotAnnotation(
      annotation: brush,
      handle: ScreenshotAnnotationResizeHandle.bottomRight,
      point: const ScreenshotAnnotationPoint(100, 60),
      imageSize: imageSize,
    ) as ScreenshotBrushAnnotation;
    final bounded = resizeScreenshotAnnotation(
      annotation: brush,
      handle: ScreenshotAnnotationResizeHandle.bottomRight,
      point: const ScreenshotAnnotationPoint(1000, 1000),
      imageSize: imageSize,
    ) as ScreenshotBrushAnnotation;

    expect((doubled.points.first.x, doubled.points.first.y), (20, 20));
    expect((doubled.points.last.x, doubled.points.last.y), (100, 60));
    expect(doubled.lineWidth, 6);
    final boundedBounds = screenshotAnnotationBounds(bounded, imageSize);
    expect(boundedBounds.right, lessThanOrEqualTo(imageSize.width));
    expect(boundedBounds.bottom, lessThanOrEqualTo(imageSize.height));

    final tinyAtEdge = ScreenshotBrushAnnotation(
      points: const [
        ScreenshotAnnotationPoint(199, 139),
        ScreenshotAnnotationPoint(200, 140),
      ],
      color: 0xff22c55e,
      lineWidth: 2,
    );
    expect(
      resizeScreenshotAnnotation(
        annotation: tinyAtEdge,
        handle: ScreenshotAnnotationResizeHandle.bottomRight,
        point: const ScreenshotAnnotationPoint(1000, 1000),
        imageSize: imageSize,
      ),
      same(tinyAtEdge),
    );
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
