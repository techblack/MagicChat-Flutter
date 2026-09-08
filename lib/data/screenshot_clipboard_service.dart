import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

import 'desktop_screenshot_types.dart';

typedef ScreenshotClipboardWriter = Future<void> Function(
  Iterable<DataWriterItem> items,
);

class ScreenshotClipboardException implements Exception {
  const ScreenshotClipboardException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScreenshotClipboardService {
  const ScreenshotClipboardService({ScreenshotClipboardWriter? writer})
      : _writer = writer;

  final ScreenshotClipboardWriter? _writer;

  Future<void> copyPng(Uint8List bytes, {required String suggestedName}) async {
    if (!_hasPngSignature(bytes)) {
      throw const ScreenshotClipboardException('截图不是有效的 PNG 图片');
    }
    if (bytes.length > desktopScreenshotMaxImageBytes) {
      throw const ScreenshotClipboardException('截图超过 32MiB，请缩小截图区域后重试');
    }

    final item = DataWriterItem(suggestedName: suggestedName);
    item.add(Formats.png(bytes));
    try {
      final writer = _writer;
      if (writer != null) {
        await writer([item]);
        return;
      }
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw const ScreenshotClipboardException('当前平台不支持图片剪贴板');
      }
      // 截图入口当前仅在桌面启用；若开放 Web，需重新确认插件能在用户激活内发起写入。
      await clipboard.write([item]);
    } on ScreenshotClipboardException {
      rethrow;
    } catch (_) {
      throw const ScreenshotClipboardException('无法写入系统剪贴板，请重试');
    }
  }
}

bool _hasPngSignature(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}
