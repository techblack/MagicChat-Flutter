import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/update_service.dart';

void main() {
  test('只接受 HTTPS 下载地址并识别新版本', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.2.0","build":2,"url":"https://example.com/app.apk"}}',
        200));
    final release = await UpdateService(client: client).check();
    expect(release?.build, 2);
    expect(release?.url, startsWith('https://'));
  });

  test('按平台选择版本清单并保留对应下载地址', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.2.0","build":2,"url":"https://example.com/app.apk"},'
        '"ios":{"version":"0.2.1","build":3,"url":"https://example.com/app.ipa"}}',
        200));
    final release =
        await UpdateService(client: client, platform: AppUpdatePlatform.ios)
            .check();
    expect(release?.version, '0.2.1');
    expect(release?.build, 3);
    expect(release?.url, 'https://example.com/app.ipa');
  });

  test('拒绝小数 build 和带空格的非 HTTPS 地址', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.2.0","build":2.5,"url":" http://example.com/app.apk "}}',
        200));
    expect(() => UpdateService(client: client).check(), throwsFormatException);
  });
}
