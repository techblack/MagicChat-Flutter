import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/update_service.dart';

import 'support/app_version.dart';

void main() {
  test('默认使用 release 更新源', () {
    expect(UpdateService.updateSource, 'release');
    expect(UpdateService.manifestUrl, UpdateService.releaseManifestUrl);
  });

  test('只接受 HTTPS 下载地址并识别新版本', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"1.2.4","build":46,"url":"https://example.com/app.apk"}}',
        200));
    final release = await UpdateService(
      appVersion: testAppVersion,
      client: client,
    ).check();
    expect(release?.build, 46);
    expect(release?.url, startsWith('https://'));
  });

  test('按平台选择版本清单并保留对应下载地址', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.3.0","build":4,"url":"https://example.com/app.apk"},'
        '"ios":{"version":"1.2.4","build":46,"url":"https://example.com/app.ipa"}}',
        200));
    final release = await UpdateService(
            appVersion: testAppVersion,
            client: client,
            platform: AppUpdatePlatform.ios)
        .check();
    expect(release?.version, '1.2.4');
    expect(release?.build, 46);
    expect(release?.url, 'https://example.com/app.ipa');
  });

  test('注入的安装包版本决定移动端更新边界', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"9.9.9","build":45,"url":"https://example.com/app.apk"}}',
        200));

    final release = await UpdateService(
      appVersion: testAppVersion,
      client: client,
    ).check();

    expect(release, isNull);
  });

  test('拒绝小数 build 和带空格的非 HTTPS 地址', () async {
    final client = MockClient((request) async => http.Response(
        '{"android":{"version":"0.2.0","build":2.5,"url":" http://example.com/app.apk "}}',
        200));
    expect(
        () => UpdateService(appVersion: testAppVersion, client: client).check(),
        throwsFormatException);
  });

  test('桌面端从 GitHub Release 选择对应平台产物', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), UpdateService.desktopReleaseApiUrl);
      expect(request.headers['user-agent'], 'MagicChat-Flutter');
      return http.Response(
          '{"tag_name":"v1.2.4","assets":[{"name":"MagicChat-Windows-x64.zip",'
          '"size":1234,"browser_download_url":"https://github.com/techblack/MagicChat-Flutter/releases/download/v1.2.4/MagicChat-Windows-x64.zip"},'
          '{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/techblack/MagicChat-Flutter/releases/download/v1.2.4/SHA256SUMS.txt"}]}',
          200);
    });
    final release = await UpdateService(
            appVersion: testAppVersion,
            client: client,
            platform: AppUpdatePlatform.windows)
        .check();
    expect(release?.version, '1.2.4');
    expect(release?.build, 1002004);
    expect(release?.url, contains('MagicChat-Windows-x64.zip'));
    expect(release?.assetName, 'MagicChat-Windows-x64.zip');
    expect(release?.size, 1234);
    expect(release?.sha256Url, endsWith('/SHA256SUMS.txt'));
  });

  test('桌面端没有对应产物时拒绝响应', () async {
    final client = MockClient(
        (_) async => http.Response('{"tag_name":"v1.2.4","assets":[]}', 200));
    expect(
        () => UpdateService(
                appVersion: testAppVersion,
                client: client,
                platform: AppUpdatePlatform.linux)
            .check(),
        throwsFormatException);
  });

  test('Linux arm64 选择对应架构的安装包', () async {
    final client = MockClient((request) async => http.Response(
        '{"tag_name":"v1.2.4","assets":['
        '{"name":"MagicChat-Linux-x64.tar.gz","size":10,"browser_download_url":"https://example.com/linux-x64.tar.gz"},'
        '{"name":"MagicChat-Linux-arm64.tar.gz","size":12,"browser_download_url":"https://example.com/linux-arm64.tar.gz"}]}',
        200));

    final release = await UpdateService(
            appVersion: testAppVersion,
            client: client,
            platform: AppUpdatePlatform.linux,
            desktopArchitecture: 'arm64')
        .check();

    expect(release?.assetName, 'MagicChat-Linux-arm64.tar.gz');
    expect(release?.url, 'https://example.com/linux-arm64.tar.gz');
    expect(release?.size, 12);
  });
}
