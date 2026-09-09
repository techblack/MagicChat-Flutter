import 'package:flutter/foundation.dart';

/// 普通文件消息的服务端上传上限。
///
/// 官方移动端允许 500 MiB；桌面端和 Web 仍使用 200 MiB。图片、语音等
/// 专用消息继续由各自的处理流程限制，不复用这个普通文件上限。
const desktopMessageFileMaxBytes = 200 * 1024 * 1024;
const mobileMessageFileMaxBytes = 500 * 1024 * 1024;

int messageFileMaxBytes({
  bool? isWeb,
  TargetPlatform? platform,
}) {
  final web = isWeb ?? kIsWeb;
  final target = platform ?? defaultTargetPlatform;
  return !web &&
          (target == TargetPlatform.android || target == TargetPlatform.iOS)
      ? mobileMessageFileMaxBytes
      : desktopMessageFileMaxBytes;
}

String messageFileSizeLimitLabel({
  bool? isWeb,
  TargetPlatform? platform,
}) =>
    messageFileMaxBytes(isWeb: isWeb, platform: platform) ==
            mobileMessageFileMaxBytes
        ? '500 MiB'
        : '200 MiB';
