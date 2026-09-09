import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/message_upload_limits.dart';

void main() {
  test('移动端普通文件上限为 500 MiB', () {
    expect(
      messageFileMaxBytes(isWeb: false, platform: TargetPlatform.android),
      mobileMessageFileMaxBytes,
    );
    expect(
      messageFileMaxBytes(isWeb: false, platform: TargetPlatform.iOS),
      mobileMessageFileMaxBytes,
    );
    expect(
      messageFileSizeLimitLabel(isWeb: false, platform: TargetPlatform.android),
      '500 MiB',
    );
  });

  test('桌面和 Web 普通文件上限保持 200 MiB', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      expect(
        messageFileMaxBytes(isWeb: false, platform: platform),
        desktopMessageFileMaxBytes,
      );
    }
    expect(
      messageFileMaxBytes(isWeb: true, platform: TargetPlatform.android),
      desktopMessageFileMaxBytes,
    );
    expect(
      messageFileSizeLimitLabel(isWeb: true, platform: TargetPlatform.android),
      '200 MiB',
    );
  });
}
