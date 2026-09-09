import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

const messageImageMaxBytes = 2 * 1024 * 1024;
const messageImageMaxDimension = 1920;

class PreparedMessageImage {
  const PreparedMessageImage({
    required this.bytes,
    required this.name,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String name;
  final int width;
  final int height;
  String get mimeType => 'image/webp';
}

class MessageImageProcessingException implements Exception {
  const MessageImageProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<PreparedMessageImage> prepareMessageImage({
  required Uint8List bytes,
  required String name,
  required String mimeType,
}) async {
  if (!_isAcceptedMessageImage(name, mimeType)) {
    throw const MessageImageProcessingException('请选择 PNG、JPG 或 WebP 图片');
  }
  late final PreparedMessageImage result;
  try {
    result = await compute(_prepareMessageImage, {
      'bytes': bytes,
      'name': name,
    });
  } catch (error) {
    if (error is MessageImageProcessingException) rethrow;
    throw const MessageImageProcessingException('读取图片失败');
  }
  return result;
}

PreparedMessageImage _prepareMessageImage(Map<String, Object> arguments) {
  final bytes = arguments['bytes']! as Uint8List;
  final name = arguments['name']! as String;
  if (bytes.isEmpty) {
    throw const MessageImageProcessingException('图片内容为空');
  }
  final decoded = image.decodeImage(bytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    throw const MessageImageProcessingException('读取图片失败');
  }

  var output = image.bakeOrientation(decoded);
  final longest = max(output.width, output.height);
  if (longest > messageImageMaxDimension) {
    final scale = messageImageMaxDimension / longest;
    output = image.copyResize(
      output,
      width: max(1, (output.width * scale).round()),
      height: max(1, (output.height * scale).round()),
      interpolation: image.Interpolation.average,
    );
  }

  var encoded = image.encodeWebP(output);
  for (var attempt = 0;
      encoded.length > messageImageMaxBytes && attempt < 8;
      attempt++) {
    final scale = min(.9, sqrt(messageImageMaxBytes / encoded.length) * .92);
    final width = max(1, (output.width * scale).floor());
    final height = max(1, (output.height * scale).floor());
    if (width == output.width && height == output.height) break;
    output = image.copyResize(
      output,
      width: width,
      height: height,
      interpolation: image.Interpolation.average,
    );
    encoded = image.encodeWebP(output);
  }
  if (encoded.length > messageImageMaxBytes) {
    throw const MessageImageProcessingException('图片压缩后仍超过 2 MiB');
  }
  final base = name.trim().replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  return PreparedMessageImage(
    bytes: encoded,
    name: '${base.isEmpty ? 'image' : base}.webp',
    width: output.width,
    height: output.height,
  );
}

bool _isAcceptedMessageImage(String name, String mimeType) {
  const acceptedTypes = {'image/jpeg', 'image/png', 'image/webp'};
  if (acceptedTypes.contains(mimeType.trim().toLowerCase())) return true;
  return RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false)
      .hasMatch(name.trim());
}
