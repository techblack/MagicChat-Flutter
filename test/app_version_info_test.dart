import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/app_version_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('从安装包元数据读取版本与构建号', () async {
    PackageInfo.setMockInitialValues(
      appName: 'MagicChat',
      packageName: 'com.magicchat.client',
      version: '2.3.4',
      buildNumber: '56',
      buildSignature: '',
    );

    final appVersion = await AppVersionInfo.load();

    expect(appVersion.version, '2.3.4');
    expect(appVersion.buildNumber, 56);
    expect(appVersion.versionWithBuild, '2.3.4+56');
  });
}
