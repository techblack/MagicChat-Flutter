import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/screenshot_clipboard_service.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  test('只向剪贴板写入原始 PNG 数据', () async {
    DataWriterItem? written;
    final service = ScreenshotClipboardService(
      writer: (items) async {
        written = items.single;
      },
    );
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await service.copyPng(png, suggestedName: 'MagicChat-test.png');

    expect(written?.suggestedName, 'MagicChat-test.png');
    final encoded = written!.data.single as EncodedData;
    expect(encoded.representations, hasLength(1));
    final representation = encoded.representations.single;
    expect(representation.format, Formats.png.providerFormat);
    expect((representation as dynamic).data as Uint8List, same(png));
  });
}
