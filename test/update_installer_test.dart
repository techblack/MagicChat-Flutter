import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/update_installer.dart';
import 'package:magicchat_client/data/update_service.dart';

void main() {
  const validApk = [0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4, 5, 6];

  test('Android 下载 APK、报告进度并打开系统安装器', () async {
    final directory =
        await Directory.systemTemp.createTemp('magicchat-update-');
    addTearDown(() => directory.delete(recursive: true));
    String? openedPath;
    final progress = <double>[];
    final installer = AndroidUpdateInstaller(
      platform: TargetPlatform.android,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url, Uri.parse('https://example.com/magicchat.apk'));
        return http.Response.bytes(validApk, 200,
            headers: {'content-length': '${validApk.length}'});
      }),
      temporaryDirectory: () async => directory,
      packageOpener: (path) async {
        openedPath = path;
        expect(await File(path).readAsBytes(), validApk);
        return true;
      },
    );

    await installer.downloadAndInstall(
      AppRelease(
          version: '0.4.0',
          build: 40,
          url: 'https://example.com/magicchat.apk',
          size: validApk.length,
          sha256: sha256.convert(validApk).toString()),
      onProgress: progress.add,
    );

    expect(openedPath, '${directory.path}/magicchat-update-40.apk');
    expect(progress, isNotEmpty);
    expect(progress.last, 1);
  });

  test('仅提供 SHA256SUMS 地址时获取并校验对应 APK 摘要', () async {
    final directory =
        await Directory.systemTemp.createTemp('magicchat-update-sums-');
    addTearDown(() => directory.delete(recursive: true));
    const assetName = 'MagicChat-Android-universal.apk';
    final digest = sha256.convert(validApk).toString();
    final requests = <Uri>[];
    var opened = false;
    final installer = AndroidUpdateInstaller(
      platform: TargetPlatform.android,
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('SHA256SUMS.txt')) {
          return http.Response('$digest  $assetName\n', 200);
        }
        return http.Response.bytes(validApk, 200,
            headers: {'content-length': '${validApk.length}'});
      }),
      temporaryDirectory: () async => directory,
      packageOpener: (_) async => opened = true,
    );

    await installer.downloadAndInstall(
      AppRelease(
        version: '0.4.0',
        build: 40,
        url:
            'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.4.0/$assetName',
        assetName: assetName,
        size: validApk.length,
        sha256Url:
            'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.4.0/SHA256SUMS.txt',
      ),
      onProgress: (_) {},
    );

    expect(requests.map((uri) => uri.pathSegments.last),
        ['SHA256SUMS.txt', assetName]);
    expect(opened, isTrue);
  });

  test('GitHub 校验文件拒绝跨站重定向', () async {
    final directory =
        await Directory.systemTemp.createTemp('magicchat-update-redirect-');
    addTearDown(() => directory.delete(recursive: true));
    const assetName = 'MagicChat-Android-universal.apk';
    final requests = <Uri>[];
    var opened = false;
    final installer = AndroidUpdateInstaller(
      platform: TargetPlatform.android,
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response('', 302,
            headers: {'location': 'https://evil.example/SHA256SUMS.txt'});
      }),
      temporaryDirectory: () async => directory,
      packageOpener: (_) async => opened = true,
    );

    await expectLater(
      installer.downloadAndInstall(
        AppRelease(
          version: '0.4.0',
          build: 40,
          url:
              'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.4.0/$assetName',
          assetName: assetName,
          size: validApk.length,
          sha256Url:
              'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.4.0/SHA256SUMS.txt',
        ),
        onProgress: (_) {},
      ),
      throwsA(isA<FormatException>()),
    );

    expect(requests, hasLength(1));
    expect(opened, isFalse);
    expect(await directory.list().toList(), isEmpty);
  });

  const invalidApk = [1, 2, 3, 4, 5, 6];
  final integrityFailures = [
    (
      name: 'SHA-256 不匹配时删除 APK 且不打开安装器',
      chunks: [validApk],
      declaredSize: validApk.length,
      releaseSize: validApk.length,
      digest: '0' * 64,
    ),
    (
      name: '实际下载小于声明长度时删除截断 APK',
      chunks: [validApk],
      declaredSize: validApk.length + 1,
      releaseSize: validApk.length + 1,
      digest: sha256.convert(validApk).toString(),
    ),
    (
      name: '实际下载超过声明长度时删除超长 APK',
      chunks: [
        validApk,
        const [7]
      ],
      declaredSize: validApk.length,
      releaseSize: validApk.length,
      digest: sha256.convert(validApk).toString(),
    ),
    (
      name: '摘要正确但 APK ZIP 文件头无效时拒绝安装并清理',
      chunks: [invalidApk],
      declaredSize: invalidApk.length,
      releaseSize: invalidApk.length,
      digest: sha256.convert(invalidApk).toString(),
    ),
  ];
  for (var index = 0; index < integrityFailures.length; index++) {
    final scenario = integrityFailures[index];
    test(scenario.name, () async {
      final result = await _runRejectedDownload(
        response: http.StreamedResponse(
          Stream.fromIterable(scenario.chunks),
          200,
          contentLength: scenario.declaredSize,
        ),
        release: AppRelease(
          version: '0.4.0',
          build: 41 + index,
          url: 'https://example.com/magicchat.apk',
          size: scenario.releaseSize,
          sha256: scenario.digest,
        ),
      );

      expect(result.error, isA<FormatException>());
      expect(result.opened, isFalse);
      expect(result.files, isEmpty);
    });
  }

  test('非 Android 平台不启用应用内安装', () {
    final installer = AndroidUpdateInstaller(platform: TargetPlatform.linux);
    expect(installer.supported, isFalse);
  });

  test('取消下载会结束任务并删除未完成 APK', () async {
    final directory =
        await Directory.systemTemp.createTemp('magicchat-update-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final client = _PendingDownloadClient();
    addTearDown(client.dispose);
    final installer = AndroidUpdateInstaller(
      platform: TargetPlatform.android,
      client: client,
      temporaryDirectory: () async => directory,
      packageOpener: (_) async => true,
    );
    final operation = installer.downloadAndInstall(
      const AppRelease(
          version: '0.4.0',
          build: 41,
          url: 'https://example.com/magicchat.apk'),
      onProgress: (_) {},
    );
    await client.requested.future;
    await Future<void>.delayed(Duration.zero);

    await installer.cancel();

    await expectLater(operation, throwsA(isA<UpdateDownloadCancelled>()));
    expect(await directory.list().toList(), isEmpty);
  });
}

Future<({Object error, List<FileSystemEntity> files, bool opened})>
    _runRejectedDownload({
  required http.StreamedResponse response,
  required AppRelease release,
}) async {
  final directory =
      await Directory.systemTemp.createTemp('magicchat-update-rejected-');
  var opened = false;
  final installer = AndroidUpdateInstaller(
    platform: TargetPlatform.android,
    client: _ResponseClient(response),
    temporaryDirectory: () async => directory,
    packageOpener: (_) async => opened = true,
  );
  Object? error;
  try {
    await installer.downloadAndInstall(release, onProgress: (_) {});
  } catch (value) {
    error = value;
  }
  final files = await directory.list().toList();
  await directory.delete(recursive: true);
  return (error: error!, files: files, opened: opened);
}

class _ResponseClient extends http.BaseClient {
  _ResponseClient(this.response);

  final http.StreamedResponse response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response;
}

class _PendingDownloadClient extends http.BaseClient {
  final requested = Completer<void>();
  final _stream = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.complete();
    return http.StreamedResponse(_stream.stream, 200, contentLength: 100);
  }

  Future<void> dispose() => _stream.close();
}
