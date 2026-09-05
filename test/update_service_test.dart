import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/update_service.dart';

void main() {
  test('默认使用 release 更新源', () {
    expect(UpdateService.updateSource, 'release');
    expect(UpdateService.manifestUrl, UpdateService.releaseManifestUrl);
    expect(UpdateService.currentVersion, '0.2.9');
    expect(UpdateService.currentBuild, 12);
  });

  test('只接受 HTTPS 下载地址并识别新版本', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.3.0","build":13,"url":"https://example.com/app.apk"}}',
        200));
    final release = await UpdateService(client: client).check();
    expect(release?.build, 13);
    expect(release?.url, startsWith('https://'));
  });

  test('按平台选择版本清单并保留对应下载地址', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.3.0","build":4,"url":"https://example.com/app.apk"},'
        '"ios":{"version":"0.3.1","build":13,"url":"https://example.com/app.ipa"}}',
        200));
    final release =
        await UpdateService(client: client, platform: AppUpdatePlatform.ios)
            .check();
    expect(release?.version, '0.3.1');
    expect(release?.build, 13);
    expect(release?.url, 'https://example.com/app.ipa');
  });

  test('拒绝小数 build 和带空格的非 HTTPS 地址', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.2.0","build":2.5,"url":" http://example.com/app.apk "}}',
        200));
    expect(() => UpdateService(client: client).check(), throwsFormatException);
  });

  test('桌面端从 GitHub Release 选择对应平台产物', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), UpdateService.desktopReleaseApiUrl);
      expect(request.headers['user-agent'], 'MagicChat-Flutter');
      return http.Response(
          '{"tag_name":"v0.3.0","assets":[{"name":"MagicChat-Windows-x64.zip",'
          '"browser_download_url":"https://github.com/techblack/MagicChat-Flutter/releases/download/v0.3.0/MagicChat-Windows-x64.zip"}]}',
          200);
    });
    final release =
        await UpdateService(client: client, platform: AppUpdatePlatform.windows)
            .check();
    expect(release?.version, '0.3.0');
    expect(release?.build, 3000);
    expect(release?.url, contains('MagicChat-Windows-x64.zip'));
  });

  test('桌面端没有对应产物时拒绝响应', () async {
    final client = MockClient(
        (_) async => http.Response('{"tag_name":"v0.3.0","assets":[]}', 200));
    expect(
        () => UpdateService(client: client, platform: AppUpdatePlatform.linux)
            .check(),
        throwsFormatException);
  });
}
