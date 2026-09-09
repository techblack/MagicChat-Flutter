import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/message_image_processor.dart';

void main() {
  test('图片发送前缩放为不超过 1920px 的 WebP', () async {
    final source = image.Image(width: 2400, height: 1200);
    image.fill(source, color: image.ColorRgb8(42, 112, 240));

    final result = await prepareMessageImage(
      bytes: Uint8List.fromList(image.encodePng(source)),
      name: '现场照片.png',
      mimeType: 'image/png',
    );

    expect(result.name, '现场照片.webp');
    expect(result.mimeType, 'image/webp');
    expect(result.width, 1920);
    expect(result.height, 960);
    expect(result.bytes.length, lessThanOrEqualTo(messageImageMaxBytes));
    final decoded = image.decodeWebP(result.bytes);
    expect(decoded?.width, 1920);
    expect(decoded?.height, 960);
  });

  test('拒绝非图片格式和无法解码的图片', () async {
    await expectLater(
      prepareMessageImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        name: '说明.pdf',
        mimeType: 'application/pdf',
      ),
      throwsA(isA<MessageImageProcessingException>()),
    );
    await expectLater(
      prepareMessageImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        name: '损坏.png',
        mimeType: 'image/png',
      ),
      throwsA(isA<MessageImageProcessingException>()),
    );
  });
}
