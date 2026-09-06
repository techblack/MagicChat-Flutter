import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/desktop_update_installer_io.dart';
import 'package:magicchat_client/data/update_installer.dart'
    hide DesktopUpdateInstaller;
import 'package:magicchat_client/data/update_service.dart';

void main() {
  group('桌面完整包更新', () {
    late Directory directory;

    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('magicchat-desktop-update-');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('下载、校验、准备 Windows 完整包后启动替换并退出', () async {
      final target = Directory('${directory.path}/MagicChat')
        ..createSync(recursive: true);
      final executable = File('${target.path}/magicchat_client.exe')
        ..writeAsBytesSync([1]);
      File('${target.path}/flutter_windows.dll').writeAsBytesSync([1]);
      Directory('${target.path}/data/flutter_assets')
          .createSync(recursive: true);
      final package = [0x50, 0x4b, 0x03, 0x04, ...List.filled(128, 7)];
      final digest = sha256.convert(package).toString();
      final requests = <Uri>[];
      DesktopUpdateInstallPlan? installPlan;
      var quit = false;
      final installer = DesktopUpdateInstaller(
        platform: TargetPlatform.windows,
        executablePath: executable.path,
        temporaryDirectory: () async => directory,
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('SHA256SUMS.txt')) {
            return http.Response('$digest  MagicChat-Windows-x64.zip\n', 200);
          }
          return http.Response.bytes(package, 200,
              headers: {'content-length': '${package.length}'});
        }),
        archiveValidator: (_, __) async {},
        archiveExtractor: (_, destination, __) async {
          await File('${destination.path}/magicchat_client.exe')
              .writeAsBytes([2]);
          await File('${destination.path}/flutter_windows.dll')
              .writeAsBytes([3]);
          await Directory('${destination.path}/data/flutter_assets')
              .create(recursive: true);
        },
        replacementLauncher: (plan) async => installPlan = plan,
        quit: () async => quit = true,
      );
      final progress = <double>[];

      await installer.downloadAndInstall(
        AppRelease(
          version: '0.3.13',
          build: 3013,
          url:
              'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.3.13/MagicChat-Windows-x64.zip',
          assetName: 'MagicChat-Windows-x64.zip',
          size: package.length,
          sha256Url:
              'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.3.13/SHA256SUMS.txt',
        ),
        onProgress: progress.add,
      );

      expect(requests.map((value) => value.pathSegments.last),
          ['SHA256SUMS.txt', 'MagicChat-Windows-x64.zip']);
      expect(progress.last, 1);
      expect(quit, isTrue);
      expect(installPlan?.targetDirectory, target.path);
      expect(installPlan?.executableRelativePath, 'magicchat_client.exe');
      expect(
          await File('${installPlan!.stagedDirectory}/magicchat_client.exe')
              .readAsBytes(),
          [2]);
      expect(await executable.readAsBytes(), [1]);
    });

    test('SHA-256 不匹配时保留旧版本且不启动替换', () async {
      final target = Directory('${directory.path}/MagicChat')
        ..createSync(recursive: true);
      final executable = File('${target.path}/magicchat_client.exe')
        ..writeAsBytesSync([1]);
      File('${target.path}/flutter_windows.dll').writeAsBytesSync([1]);
      Directory('${target.path}/data/flutter_assets')
          .createSync(recursive: true);
      final package = [0x50, 0x4b, 0x03, 0x04, ...List.filled(32, 5)];
      var launched = false;
      final installer = DesktopUpdateInstaller(
        platform: TargetPlatform.windows,
        executablePath: executable.path,
        temporaryDirectory: () async => directory,
        client: MockClient((request) async => http.Response.bytes(package, 200,
            headers: {'content-length': '${package.length}'})),
        archiveValidator: (_, __) async {},
        archiveExtractor: (_, __, ___) async {},
        replacementLauncher: (_) async => launched = true,
        quit: () async {},
      );

      await expectLater(
        installer.downloadAndInstall(
          AppRelease(
            version: '0.3.13',
            build: 3013,
            url: 'https://example.com/MagicChat-Windows-x64.zip',
            assetName: 'MagicChat-Windows-x64.zip',
            size: package.length,
            sha256: '0' * 64,
          ),
          onProgress: (_) {},
        ),
        throwsA(isA<FormatException>()),
      );

      expect(launched, isFalse);
      expect(await executable.readAsBytes(), [1]);
      expect(
          directory
              .listSync()
              .where((entry) => entry.path.contains('magicchat-update-')),
          isEmpty);
    });

    test('可取消未完成的桌面安装包下载并清理临时文件', () async {
      final target = Directory('${directory.path}/MagicChat')
        ..createSync(recursive: true);
      final executable = File('${target.path}/magicchat_client.exe')
        ..writeAsBytesSync([1]);
      File('${target.path}/flutter_windows.dll').writeAsBytesSync([1]);
      Directory('${target.path}/data/flutter_assets')
          .createSync(recursive: true);
      final client = _PendingDownloadClient();
      addTearDown(client.dispose);
      final installer = DesktopUpdateInstaller(
        platform: TargetPlatform.windows,
        executablePath: executable.path,
        temporaryDirectory: () async => directory,
        client: client,
        archiveValidator: (_, __) async {},
        archiveExtractor: (_, __, ___) async {},
        replacementLauncher: (_) async {},
        quit: () async {},
      );
      final operation = installer.downloadAndInstall(
        const AppRelease(
          version: '0.3.13',
          build: 3013,
          url: 'https://example.com/MagicChat-Windows-x64.zip',
          assetName: 'MagicChat-Windows-x64.zip',
        ),
        onProgress: (_) {},
      );
      await client.requested.future;

      await installer.cancel();

      await expectLater(operation, throwsA(isA<UpdateDownloadCancelled>()));
      expect(
          directory.listSync().where((entry) => entry.path.endsWith('.part')),
          isEmpty);
    });

    test('官方 Release 下载拒绝跳转到非 GitHub 资产域名', () async {
      final installer = DesktopUpdateInstaller(
        platform: TargetPlatform.windows,
        executablePath: '${directory.path}/MagicChat/magicchat_client.exe',
        temporaryDirectory: () async => directory,
        client: MockClient((_) async => http.Response('', 302,
            headers: {'location': 'https://evil.example/update.zip'})),
        archiveValidator: (_, __) async {},
        archiveExtractor: (_, __, ___) async {},
        replacementLauncher: (_) async {},
        quit: () async {},
      );

      await expectLater(
          installer.downloadAndInstall(
            AppRelease(
              version: '0.3.13',
              build: 3013,
              url:
                  'https://github.com/techblack/MagicChat-Flutter/releases/download/v0.3.13/MagicChat-Windows-x64.zip',
              assetName: 'MagicChat-Windows-x64.zip',
              sha256: '0' * 64,
            ),
            onProgress: (_) {},
          ),
          throwsFormatException);
    });

    test('校验文件严格按安装包文件名提取摘要', () {
      final a = 'a' * 64;
      final b = 'b' * 64;
      expect(
          parseSha256Sums('$a  other.zip\n$b *MagicChat-Linux-x64.tar.gz\n',
              'MagicChat-Linux-x64.tar.gz'),
          b);
      expect(() => parseSha256Sums('$a  other.zip\n', 'missing.zip'),
          throwsFormatException);
    });

    test('归档路径拒绝穿越、绝对路径和越界符号链接', () {
      expect(isSafeDesktopArchiveEntry('data/flutter_assets/a', null), isTrue);
      expect(isSafeDesktopArchiveEntry('../outside', null), isFalse);
      expect(isSafeDesktopArchiveEntry('/etc/passwd', null), isFalse);
      expect(isSafeDesktopArchiveEntry(r'C:\Windows\file', null), isFalse);
      expect(
          isSafeDesktopArchiveEntry('lib/current', '../version/lib'), isTrue);
      expect(
          isSafeDesktopArchiveEntry('lib/current', '../../outside'), isFalse);
    });

    test('真实 ZIP 校验在解压前拒绝路径穿越', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('../outside.txt', 'invalid'));
      final file = File('${directory.path}/malicious.zip.part');
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));

      await expectLater(
          validateDesktopUpdateArchive(file, TargetPlatform.windows),
          throwsFormatException);
      expect(
          await File('${directory.parent.path}/outside.txt').exists(), isFalse);
    });

    test('真实 Linux tar.gz 可通过校验并安全解包', () async {
      if (!Platform.isLinux) return;
      final archive = Archive()
        ..addFile(ArchiveFile.string('magicchat_client', 'binary'))
        ..addFile(ArchiveFile.string(
            'data/flutter_assets/AssetManifest.bin', 'asset'))
        ..addFile(ArchiveFile.string('lib/libflutter_linux_gtk.so', 'library'));
      final tar = TarEncoder().encodeBytes(archive);
      final package = File('${directory.path}/MagicChat-Linux-x64.tar.gz');
      await package.writeAsBytes(GZipEncoder().encodeBytes(tar));
      final extracted = Directory('${directory.path}/extracted')
        ..createSync(recursive: true);

      await validateDesktopUpdateArchive(package, TargetPlatform.linux);
      await extractDesktopUpdateArchive(
          package, extracted, TargetPlatform.linux);

      expect(await File('${extracted.path}/magicchat_client').readAsString(),
          'binary');
      expect(
          await File('${extracted.path}/lib/libflutter_linux_gtk.so').exists(),
          isTrue);
    });

    test('Linux 替换助手在新版本启动失败时恢复并重启旧版本', () async {
      if (!Platform.isLinux) return;
      final target = Directory('${directory.path}/app')
        ..createSync(recursive: true);
      final staged = Directory('${directory.path}/app.update')
        ..createSync(recursive: true);
      final marker = File('${directory.path}/old-restarted');
      final oldExecutable = File('${target.path}/magicchat_client');
      final newExecutable = File('${staged.path}/magicchat_client');
      await oldExecutable
          .writeAsString('#!/bin/sh\ntouch "${marker.path}"\nexit 0\n');
      await newExecutable.writeAsString('#!/bin/sh\nexit 1\n');
      await Process.run('chmod', ['700', oldExecutable.path]);
      await Process.run('chmod', ['700', newExecutable.path]);

      await launchDesktopReplacement(DesktopUpdateInstallPlan(
        platform: TargetPlatform.linux,
        parentPid: 2147483647,
        targetDirectory: target.path,
        stagedDirectory: staged.path,
        backupDirectory: '${directory.path}/app.backup',
        executableRelativePath: 'magicchat_client',
      ));
      for (var attempt = 0; attempt < 40 && !await marker.exists(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(await marker.exists(), isTrue);
      expect(await oldExecutable.readAsString(), contains('old-restarted'));
      expect(await staged.exists(), isFalse);
    });

    test('三平台替换脚本都包含备份、重启和失败恢复路径', () {
      expect(windowsDesktopReplacementScript, contains('Move-Item'));
      expect(windowsDesktopReplacementScript, contains('Start-Process'));
      expect(windowsDesktopReplacementScript, contains(r'$Backup'));
      expect(macOSDesktopReplacementScript, contains(r'open -n "$target"'));
      expect(
          macOSDesktopReplacementScript, contains(r'mv "$backup" "$target"'));
      expect(
          linuxDesktopReplacementScript, contains(r'mv "$backup" "$target"'));
      expect(linuxDesktopReplacementScript, contains(r'kill -0 "$new_pid"'));
    });
  });
}

class _PendingDownloadClient extends http.BaseClient {
  final requested = Completer<void>();
  final _stream = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requested.isCompleted) requested.complete();
    return http.StreamedResponse(_stream.stream, 200, contentLength: 100);
  }

  Future<void> dispose() => _stream.close();
}
