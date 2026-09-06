import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'update_installer_types.dart';
import 'update_service.dart';

class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({
    http.Client? client,
    TargetPlatform? platform,
    Future<Directory> Function()? temporaryDirectory,
    UpdatePackageOpener? packageOpener,
  })  : _client = client,
        _platform = platform,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _packageOpener = packageOpener ?? _openPackage;

  static const _apkMimeType = 'application/vnd.android.package-archive';

  final http.Client? _client;
  final TargetPlatform? _platform;
  final Future<Directory> Function() _temporaryDirectory;
  final UpdatePackageOpener _packageOpener;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _downloadCompleter;
  http.Client? _activeClient;
  bool _ownsActiveClient = false;
  bool _running = false;

  @override
  bool get supported =>
      !kIsWeb && (_platform ?? defaultTargetPlatform) == TargetPlatform.android;

  @override
  String get progressLabel => '正在下载安装包';

  @override
  String get completionHint => '下载完成后将打开系统安装器，请按系统提示完成更新。';

  @override
  Future<void> downloadAndInstall(
    AppRelease release, {
    required UpdateDownloadProgress onProgress,
  }) async {
    if (!supported) {
      throw UnsupportedError('当前平台不支持应用内安装更新');
    }
    if (_running) throw StateError('已有安装包正在下载');
    final uri = Uri.parse(release.url);
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('安装包下载地址必须使用 HTTPS');
    }

    _running = true;
    final client = _activeClient = _client ?? http.Client();
    _ownsActiveClient = _client == null;
    File? file;
    IOSink? sink;

    try {
      final directory = await _temporaryDirectory();
      await directory.create(recursive: true);
      file = File('${directory.path}/magicchat-update-${release.build}.apk');
      if (await file.exists()) await file.delete();
      sink = file.openWrite();
      final completion = Completer<void>();
      _downloadCompleter = completion;
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('安装包下载失败（HTTP ${response.statusCode}）');
      }
      var received = 0;
      final total = response.contentLength ?? 0;
      _subscription = response.stream.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress((received / total).clamp(0, 1));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completion.isCompleted) completion.complete();
        },
        cancelOnError: true,
      );
      await completion.future;
      await sink.flush();
      await sink.close();
      sink = null;
      _subscription = null;
      _downloadCompleter = null;
      onProgress(1);
      if (!await _packageOpener(file.path)) {
        throw Exception('无法打开系统安装器');
      }
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      _downloadCompleter = null;
      await sink?.close();
      if (file != null && await file.exists()) await file.delete();
      rethrow;
    } finally {
      if (_ownsActiveClient) client.close();
      _activeClient = null;
      _ownsActiveClient = false;
      _running = false;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    final completion = _downloadCompleter;
    await _subscription?.cancel();
    _subscription = null;
    if (completion != null && !completion.isCompleted) {
      completion.completeError(const UpdateDownloadCancelled());
    }
    if (_ownsActiveClient) _activeClient?.close();
  }

  static Future<bool> _openPackage(String filePath) async =>
      (await OpenFilex.open(filePath, type: _apkMimeType)).type ==
      ResultType.done;
}
