import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  static const _maximumPackageBytes = 4 * 1024 * 1024 * 1024;
  static const _maximumChecksumBytes = 1024 * 1024;

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
      final assetName = _releaseAssetName(release);
      final expectedSha256 = await _expectedSha256(client, release, assetName);
      final directory = await _temporaryDirectory();
      await directory.create(recursive: true);
      file = File('${directory.path}/magicchat-update-${release.build}.apk');
      if (await file.exists()) await file.delete();
      sink = file.openWrite();
      final digestSink = _DigestSink();
      final digestConverter = sha256.startChunkedConversion(digestSink);
      final completion = Completer<void>();
      _downloadCompleter = completion;
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('安装包下载失败（HTTP ${response.statusCode}）');
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null &&
          (declaredLength <= 0 ||
              declaredLength > _maximumPackageBytes ||
              (release.size != null && declaredLength != release.size))) {
        throw const FormatException('安装包大小与发布信息不一致');
      }
      var received = 0;
      final total = release.size ?? declaredLength ?? 0;
      _subscription = response.stream.listen(
        (chunk) {
          sink!.add(chunk);
          digestConverter.add(chunk);
          received += chunk.length;
          if (received > _maximumPackageBytes ||
              (release.size != null && received > release.size!)) {
            if (!completion.isCompleted) {
              completion.completeError(const FormatException('安装包大小不正确'));
            }
            return;
          }
          if (total > 0) onProgress((received / total).clamp(0, .96));
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
      digestConverter.close();
      _subscription = null;
      _downloadCompleter = null;
      if (received <= 0 ||
          (release.size != null && received != release.size) ||
          (declaredLength != null && received != declaredLength)) {
        throw const FormatException('安装包下载不完整');
      }
      if (expectedSha256 != null &&
          digestSink.value?.toString() != expectedSha256) {
        throw const FormatException('安装包 SHA-256 校验失败');
      }
      await _validateApkHeader(file);
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

  Future<String?> _expectedSha256(
      http.Client client, AppRelease release, String assetName) async {
    final direct = release.sha256?.trim().toLowerCase();
    if (direct != null) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(direct)) {
        throw const FormatException('发布信息中的 SHA-256 不正确');
      }
      return direct;
    }
    final checksumUrl = release.sha256Url;
    if (checksumUrl == null) return null;
    final uri = Uri.tryParse(checksumUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('校验文件地址必须使用 HTTPS');
    }
    final response = await _sendChecksumRequest(client, uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('校验文件下载失败（HTTP ${response.statusCode}）');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length > _maximumChecksumBytes) {
        throw const FormatException('校验文件过大');
      }
    }
    return _parseSha256Sums(utf8.decode(bytes.takeBytes()), assetName);
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

String _releaseAssetName(AppRelease release) {
  final explicit = release.assetName?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final segments = Uri.parse(release.url).pathSegments;
  if (segments.isEmpty || segments.last.isEmpty) {
    throw const FormatException('安装包文件名不正确');
  }
  return segments.last;
}

Future<http.StreamedResponse> _sendChecksumRequest(
    http.Client client, Uri initialUri) async {
  final official = initialUri.host.toLowerCase() == 'github.com';
  var uri = initialUri;
  for (var redirects = 0; redirects <= 3; redirects++) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('校验文件地址必须使用 HTTPS');
    }
    if (official && !_isAllowedOfficialChecksumUri(uri)) {
      throw const FormatException('校验文件重定向来源不可信');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'text/plain',
        'Cache-Control': 'no-cache',
      });
    final response =
        await client.send(request).timeout(const Duration(seconds: 30));
    if (!_isRedirectStatus(response.statusCode)) return response;
    if (redirects == 3) throw const FormatException('校验文件重定向次数过多');
    final location = response.headers['location'];
    await response.stream.drain<void>();
    if (location == null || location.trim().isEmpty) {
      throw const FormatException('校验文件重定向缺少地址');
    }
    uri = uri.resolve(location.trim());
  }
  throw const FormatException('校验文件重定向次数过多');
}

bool _isAllowedOfficialChecksumUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host == 'github.com') {
    return uri.path
            .startsWith('/techblack/MagicChat-Flutter/releases/download/') &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last == 'SHA256SUMS.txt';
  }
  return host == 'release-assets.githubusercontent.com' ||
      host == 'objects.githubusercontent.com';
}

bool _isRedirectStatus(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;

String _parseSha256Sums(String source, String assetName) {
  String? result;
  for (final line in const LineSplitter().convert(source)) {
    final match =
        RegExp(r'^([0-9a-fA-F]{64})[ \t]+[* ]?(.+)$').firstMatch(line);
    if (match == null || match.group(2)?.trim() != assetName) continue;
    final value = match.group(1)!.toLowerCase();
    if (result != null && result != value) {
      throw const FormatException('校验文件包含冲突的 SHA-256');
    }
    result = value;
  }
  if (result == null) throw const FormatException('校验文件缺少当前安装包');
  return result;
}

Future<void> _validateApkHeader(File file) async {
  final source = await file.open();
  try {
    final header = await source.read(4);
    if (header.length < 4 ||
        header[0] != 0x50 ||
        header[1] != 0x4b ||
        header[2] != 0x03 ||
        header[3] != 0x04) {
      throw const FormatException('APK 安装包文件头不正确');
    }
  } finally {
    await source.close();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
