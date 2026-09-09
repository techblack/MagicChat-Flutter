import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android JPush 使用官方默认 AppKey 并允许环境变量覆盖', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle,
        contains('val defaultJPushAppKey = "d7fa4b31dd21064e095d29d5"'));
    expect(
      gradle,
      contains('System.getenv("JPUSH_APP_KEY")?.trim()'),
    );
    expect(gradle, contains('?: defaultJPushAppKey'));
    expect(gradle, contains('implementation("cn.jiguang.sdk:jpush:6.2.0")'));
    expect(gradle, isNot(contains('JPUSH_MASTER_SECRET')));
    expect(gradle, isNot(contains('MASTER_SECRET')));
  });
}
