import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/update_installer.dart';
import 'package:magicchat_client/data/update_service.dart';

void main() {
  test('Android 下载 APK、报告进度并打开系统安装器', () async {
    final directory =
        await Directory.systemTemp.createTemp('magicchat-update-');
    addTearDown(() => directory.delete(recursive: true));
    const bytes = [1, 2, 3, 4, 5, 6];
    String? openedPath;
    final progress = <double>[];
    final installer = AndroidUpdateInstaller(
      platform: TargetPlatform.android,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url, Uri.parse('https://example.com/magicchat.apk'));
        return http.Response.bytes(bytes, 200,
            headers: {'content-length': '${bytes.length}'});
      }),
      temporaryDirectory: () async => directory,
      packageOpener: (path) async {
        openedPath = path;
        expect(await File(path).readAsBytes(), bytes);
        return true;
      },
    );

    await installer.downloadAndInstall(
      const AppRelease(
          version: '0.4.0',
          build: 40,
          url: 'https://example.com/magicchat.apk'),
      onProgress: progress.add,
    );

    expect(openedPath, '${directory.path}/magicchat-update-40.apk');
    expect(progress, isNotEmpty);
    expect(progress.last, 1);
  });

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
