import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'desktop_window_controller.dart';
import 'update_installer_types.dart';
import 'update_service.dart';

typedef DesktopArchiveValidator = Future<void> Function(
    File archive, TargetPlatform platform);
typedef DesktopArchiveExtractor = Future<void> Function(
    File archive, Directory destination, TargetPlatform platform);
typedef DesktopReplacementLauncher = Future<void> Function(
    DesktopUpdateInstallPlan plan);
typedef DesktopUpdateQuitter = Future<void> Function();

class DesktopUpdateInstallPlan {
  const DesktopUpdateInstallPlan({
    required this.platform,
    required this.parentPid,
    required this.targetDirectory,
    required this.stagedDirectory,
    required this.backupDirectory,
    required this.executableRelativePath,
  });

  final TargetPlatform platform;
  final int parentPid;
  final String targetDirectory;
  final String stagedDirectory;
  final String backupDirectory;
  final String executableRelativePath;
}

class DesktopUpdateInstaller implements UpdateInstaller {
  DesktopUpdateInstaller({
    http.Client? client,
    TargetPlatform? platform,
    String? executablePath,
    Future<Directory> Function()? temporaryDirectory,
    DesktopArchiveValidator? archiveValidator,
    DesktopArchiveExtractor? archiveExtractor,
    DesktopReplacementLauncher? replacementLauncher,
    DesktopUpdateQuitter? quit,
  })  : _client = client,
        _platform = platform,
        _executablePath = executablePath ?? Platform.resolvedExecutable,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _archiveValidator = archiveValidator ?? validateDesktopUpdateArchive,
        _archiveExtractor = archiveExtractor ?? extractDesktopUpdateArchive,
        _replacementLauncher = replacementLauncher ?? launchDesktopReplacement,
        _quit = quit ?? const PlatformDesktopWindowController().quit;

  static const _maximumPackageBytes = 4 * 1024 * 1024 * 1024;
  static const _maximumChecksumBytes = 1024 * 1024;

  final http.Client? _client;
  final TargetPlatform? _platform;
  final String _executablePath;
  final Future<Directory> Function() _temporaryDirectory;
  final DesktopArchiveValidator _archiveValidator;
  final DesktopArchiveExtractor _archiveExtractor;
  final DesktopReplacementLauncher _replacementLauncher;
  final DesktopUpdateQuitter _quit;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _downloadCompleter;
  http.Client? _activeClient;
  bool _ownsActiveClient = false;
  bool _running = false;
  bool _cancelled = false;

  TargetPlatform get _targetPlatform => _platform ?? defaultTargetPlatform;

  @override
  bool get supported =>
      !kIsWeb &&
      (_targetPlatform == TargetPlatform.windows ||
          _targetPlatform == TargetPlatform.macOS ||
          _targetPlatform == TargetPlatform.linux);

  @override
  String get progressLabel => '正在下载并校验完整安装包';

  @override
  String get completionHint => '校验完成后将自动替换当前版本并重启。';

  @override
  Future<void> downloadAndInstall(
    AppRelease release, {
    required UpdateDownloadProgress onProgress,
  }) async {
    if (!supported) throw UnsupportedError('当前平台不支持应用内安装更新');
    if (_running) throw StateError('已有安装包正在下载');
    final uri = Uri.tryParse(release.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('安装包下载地址必须使用 HTTPS');
    }
    final assetName = _releaseAssetName(release);
    _validateAssetName(assetName, _targetPlatform);

    _running = true;
    _cancelled = false;
    final client = _activeClient = _client ?? http.Client();
    _ownsActiveClient = _client == null;
    File? archive;
    Directory? staged;
    Directory? extracting;
    IOSink? sink;
    try {
      final expectedSha256 = await _expectedSha256(client, release, assetName);
      _checkCancelled();
      final directory = await _temporaryDirectory();
      await directory.create(recursive: true);
      archive = File(p.join(
          directory.path, 'magicchat-update-${release.build}-$assetName.part'));
      if (await archive.exists()) await archive.delete();
      sink = archive.openWrite();
      final digestSink = _DigestSink();
      final digestConverter = sha256.startChunkedConversion(digestSink);
      final completion = Completer<void>();
      _downloadCompleter = completion;
      final response = await _sendDesktopUpdateRequest(client, uri, assetName);
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
          if (total > 0) {
            onProgress((received / total).clamp(0, .96));
          }
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
      _checkCancelled();
      if (received <= 0 ||
          (release.size != null && received != release.size) ||
          (declaredLength != null && received != declaredLength)) {
        throw const FormatException('安装包下载不完整');
      }
      final actualSha256 = digestSink.value?.toString();
      if (expectedSha256 != null && actualSha256 != expectedSha256) {
        throw const FormatException('安装包 SHA-256 校验失败');
      }
      await _validatePackageHeader(archive, _targetPlatform);
      final completedArchive = File(p.join(
          directory.path, 'magicchat-update-${release.build}-$assetName'));
      if (await completedArchive.exists()) await completedArchive.delete();
      archive = await archive.rename(completedArchive.path);
      await _archiveValidator(archive, _targetPlatform);
      onProgress(.98);
      _checkCancelled();

      final targetPath = desktopInstallationRoot(
          _targetPlatform, File(_executablePath).absolute.path);
      final target = Directory(targetPath);
      if (!await target.exists()) throw Exception('找不到当前桌面安装目录');
      await _validateCurrentInstallation(
          target, _targetPlatform, File(_executablePath).absolute.path);
      staged = Directory('$targetPath.magicchat-update-${release.build}');
      extracting = Directory('$targetPath.magicchat-extract-${release.build}');
      final backup = Directory('$targetPath.magicchat-backup-${release.build}');
      if (await staged.exists() ||
          await extracting.exists() ||
          await backup.exists()) {
        throw Exception('检测到未完成的桌面更新，请先重新启动应用后再试');
      }
      await extracting.create(recursive: false);
      await _archiveExtractor(archive, extracting, _targetPlatform);
      final payload = await _validateExtractedPayload(
          extracting, _targetPlatform, release.version);
      if (p.equals(payload.path, extracting.path)) {
        await extracting.rename(staged.path);
        extracting = null;
      } else {
        await payload.rename(staged.path);
        await extracting.delete(recursive: true);
        extracting = null;
      }
      final executableRelativePath =
          desktopExecutableRelativePath(_targetPlatform);
      if (_targetPlatform == TargetPlatform.linux) {
        final chmod = await Process.run(
            'chmod', ['700', p.join(staged.path, executableRelativePath)]);
        if (chmod.exitCode != 0) throw Exception('无法设置新版本可执行权限');
      }
      _checkCancelled();
      onProgress(1);
      await archive.delete();
      archive = null;
      await _replacementLauncher(DesktopUpdateInstallPlan(
        platform: _targetPlatform,
        parentPid: pid,
        targetDirectory: target.path,
        stagedDirectory: staged.path,
        backupDirectory: backup.path,
        executableRelativePath: executableRelativePath,
      ));
      await _quit();
      staged = null;
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      _downloadCompleter = null;
      await sink?.close();
      if (archive != null && await archive.exists()) await archive.delete();
      if (extracting != null && await extracting.exists()) {
        await extracting.delete(recursive: true);
      }
      if (staged != null && await staged.exists()) {
        await staged.delete(recursive: true);
      }
      rethrow;
    } finally {
      if (_ownsActiveClient) client.close();
      _activeClient = null;
      _ownsActiveClient = false;
      _running = false;
      _cancelled = false;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelled = true;
    final completion = _downloadCompleter;
    await _subscription?.cancel();
    _subscription = null;
    if (completion != null && !completion.isCompleted) {
      completion.completeError(const UpdateDownloadCancelled());
    }
    if (_ownsActiveClient) _activeClient?.close();
  }

  void _checkCancelled() {
    if (_cancelled) throw const UpdateDownloadCancelled();
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
    final response = await _sendDesktopUpdateRequest(
        client, uri, 'SHA256SUMS.txt',
        accept: 'text/plain');
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
    return parseSha256Sums(utf8.decode(bytes.takeBytes()), assetName);
  }
}

Future<http.StreamedResponse> _sendDesktopUpdateRequest(
    http.Client client, Uri initialUri, String expectedFileName,
    {String accept = 'application/octet-stream'}) async {
  final official = initialUri.host.toLowerCase() == 'github.com';
  var uri = initialUri;
  for (var redirects = 0; redirects <= 3; redirects++) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('桌面更新下载地址必须使用 HTTPS');
    }
    if (official && !_isAllowedOfficialUpdateUri(uri, expectedFileName)) {
      throw const FormatException('桌面更新重定向来源不可信');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({'Accept': accept, 'Cache-Control': 'no-cache'});
    final response = await client.send(request).timeout(
          expectedFileName == 'SHA256SUMS.txt'
              ? const Duration(seconds: 30)
              : const Duration(minutes: 30),
        );
    if (!_isRedirectStatus(response.statusCode)) return response;
    if (redirects == 3) throw const FormatException('桌面更新重定向次数过多');
    final location = response.headers['location'];
    await response.stream.drain<void>();
    if (location == null || location.trim().isEmpty) {
      throw const FormatException('桌面更新重定向缺少地址');
    }
    uri = uri.resolve(location.trim());
  }
  throw const FormatException('桌面更新重定向次数过多');
}

bool _isAllowedOfficialUpdateUri(Uri uri, String expectedFileName) {
  final host = uri.host.toLowerCase();
  if (host == 'github.com') {
    return uri.path
            .startsWith('/techblack/MagicChat-Flutter/releases/download/') &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last == expectedFileName;
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

String parseSha256Sums(String source, String assetName) {
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

String desktopInstallationRoot(TargetPlatform platform, String executablePath) {
  final absolute = File(executablePath).absolute.path;
  if (platform != TargetPlatform.macOS) return p.dirname(absolute);
  final normalized = absolute.replaceAll('\\', '/');
  const marker = '.app/Contents/MacOS/';
  final index = normalized.toLowerCase().indexOf(marker.toLowerCase());
  if (index < 0) throw Exception('当前应用不是可更新的 macOS App 安装');
  return normalized.substring(0, index + 4);
}

String desktopExecutableRelativePath(TargetPlatform platform) =>
    platform == TargetPlatform.windows
        ? 'magicchat_client.exe'
        : platform == TargetPlatform.macOS
            ? p.join('Contents', 'MacOS', 'MagicChat')
            : 'magicchat_client';

Future<void> validateDesktopUpdateArchive(
    File source, TargetPlatform platform) async {
  final lower = source.path.toLowerCase();
  Archive archive;
  InputFileStream? input;
  File? temporaryTar;
  try {
    if (platform == TargetPlatform.linux) {
      final listing = await Process.run(
          '/bin/tar', ['--list', '--verbose', '--gzip', '--file', source.path]);
      if (listing.exitCode != 0 ||
          const LineSplitter()
              .convert('${listing.stdout}')
              .where((line) => line.isNotEmpty)
              .any((line) => !const {'-', 'd', 'l'}.contains(line[0]))) {
        throw const FormatException('Linux 安装包包含不支持的归档条目');
      }
      temporaryTar = File('${source.path}.validate.tar');
      final compressed = InputFileStream(source.path);
      final output = OutputFileStream(temporaryTar.path);
      try {
        const GZipDecoder().decodeStream(compressed, output, verify: true);
      } finally {
        await compressed.close();
        await output.close();
      }
      input = InputFileStream(temporaryTar.path);
      archive = TarDecoder().decodeStream(input);
    } else {
      if (!lower.endsWith('.zip') && !lower.endsWith('.zip.part')) {
        throw const FormatException('桌面安装包扩展名不正确');
      }
      input = InputFileStream(source.path);
      archive = ZipDecoder().decodeStream(input, verify: true);
    }
    var entries = 0;
    var totalSize = 0;
    for (final entry in archive) {
      entries++;
      totalSize += entry.size;
      if (entries > 100000 ||
          entry.size < 0 ||
          totalSize > 8 * 1024 * 1024 * 1024 ||
          !isSafeDesktopArchiveEntry(entry.name, entry.symbolicLink)) {
        throw const FormatException('桌面安装包包含不安全的归档路径');
      }
    }
    if (entries == 0) throw const FormatException('桌面安装包为空');
    await archive.clear();
  } on ArchiveException catch (error) {
    throw FormatException('桌面安装包损坏：${error.message}');
  } finally {
    await input?.close();
    if (temporaryTar != null && await temporaryTar.exists()) {
      await temporaryTar.delete();
    }
  }
}

bool isSafeDesktopArchiveEntry(String name, String? symbolicLink) {
  final path = name.replaceAll('\\', '/');
  if (path.contains('\u0000') ||
      path.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    return false;
  }
  final segments = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return false;
    segments.add(part);
  }
  if (symbolicLink == null || symbolicLink.isEmpty) return true;
  final target = symbolicLink.replaceAll('\\', '/');
  if (target.contains('\u0000') ||
      target.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(target)) {
    return false;
  }
  if (segments.isNotEmpty) segments.removeLast();
  for (final part in target.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isEmpty) return false;
      segments.removeLast();
    } else {
      segments.add(part);
    }
  }
  return true;
}

Future<void> extractDesktopUpdateArchive(
    File archive, Directory destination, TargetPlatform platform) async {
  final ProcessResult result;
  if (platform == TargetPlatform.windows) {
    result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $args[0] -DestinationPath $args[1] -Force",
      archive.path,
      destination.path,
    ]);
  } else if (platform == TargetPlatform.macOS) {
    result = await Process.run(
        '/usr/bin/ditto', ['-x', '-k', archive.path, destination.path]);
  } else {
    result = await Process.run('/bin/tar', [
      '--extract',
      '--gzip',
      '--file',
      archive.path,
      '--directory',
      destination.path,
      '--no-same-owner',
      '--no-same-permissions',
    ]);
  }
  if (result.exitCode != 0) {
    throw Exception('桌面安装包解压失败：${'${result.stderr}'.trim()}');
  }
}

Future<void> launchDesktopReplacement(DesktopUpdateInstallPlan plan) async {
  if (plan.platform == TargetPlatform.windows) {
    final helper = File(p.join(Directory.systemTemp.path,
        'magicchat-update-${DateTime.now().microsecondsSinceEpoch}.ps1'));
    await helper.writeAsString(windowsDesktopReplacementScript, flush: true);
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        helper.path,
        '${plan.parentPid}',
        plan.targetDirectory,
        plan.stagedDirectory,
        plan.backupDirectory,
        plan.executableRelativePath,
      ],
      mode: ProcessStartMode.detached,
    );
    return;
  }
  final script = plan.platform == TargetPlatform.macOS
      ? macOSDesktopReplacementScript
      : linuxDesktopReplacementScript;
  await Process.start(
    '/bin/sh',
    [
      '-c',
      script,
      'magicchat-package-updater',
      '${plan.parentPid}',
      plan.targetDirectory,
      plan.stagedDirectory,
      plan.backupDirectory,
      plan.executableRelativePath,
    ],
    mode: ProcessStartMode.detached,
  );
}

const linuxDesktopReplacementScript = r'''
parent_pid="$1"
target="$2"
staged="$3"
backup="$4"
relative_executable="$5"
while kill -0 "$parent_pid" 2>/dev/null; do sleep 1; done
if ! mv "$target" "$backup"; then exit 1; fi
if mv "$staged" "$target"; then
  chmod 700 "$target/$relative_executable"
  (cd "$target" && "./$relative_executable" >/dev/null 2>&1) &
  new_pid=$!
  sleep 1
  if kill -0 "$new_pid" 2>/dev/null; then
    rm -rf "$backup"
    exit 0
  fi
fi
rm -rf "$target"
mv "$backup" "$target"
(cd "$target" && "./$relative_executable" >/dev/null 2>&1) &
exit 1
''';

const macOSDesktopReplacementScript = r'''
parent_pid="$1"
target="$2"
staged="$3"
backup="$4"
while kill -0 "$parent_pid" 2>/dev/null; do sleep 1; done
if ! mv "$target" "$backup"; then exit 1; fi
if mv "$staged" "$target" && open -n "$target"; then
  sleep 1
  rm -rf "$backup"
  exit 0
fi
rm -rf "$target"
mv "$backup" "$target"
open -n "$target"
exit 1
''';

const windowsDesktopReplacementScript = r'''
param(
  [int]$OldPid,
  [string]$Target,
  [string]$Staged,
  [string]$Backup,
  [string]$RelativeExecutable
)
$ErrorActionPreference = 'Stop'
Wait-Process -Id $OldPid -ErrorAction SilentlyContinue
try {
  Move-Item -LiteralPath $Target -Destination $Backup
  Move-Item -LiteralPath $Staged -Destination $Target
  $Executable = Join-Path $Target $RelativeExecutable
  $Child = Start-Process -FilePath $Executable -WorkingDirectory $Target -PassThru
  Start-Sleep -Seconds 1
  if ($Child.HasExited) { throw 'updated process exited during startup' }
  Remove-Item -LiteralPath $Backup -Recurse -Force
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
  exit 0
} catch {
  Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $Backup) {
    Move-Item -LiteralPath $Backup -Destination $Target
    Start-Process -FilePath (Join-Path $Target $RelativeExecutable) -WorkingDirectory $Target
  }
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
  exit 1
}
''';

String _releaseAssetName(AppRelease release) {
  final explicit = release.assetName?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final segments = Uri.parse(release.url).pathSegments;
  if (segments.isEmpty || segments.last.isEmpty) {
    throw const FormatException('安装包文件名不正确');
  }
  return segments.last;
}

void _validateAssetName(String assetName, TargetPlatform platform) {
  final expected = platform == TargetPlatform.windows
      ? 'MagicChat-Windows-x64.zip'
      : platform == TargetPlatform.macOS
          ? 'MagicChat-macOS.zip'
          : 'MagicChat-Linux-x64.tar.gz';
  if (assetName != expected) {
    throw FormatException('安装包与当前平台不匹配：$assetName');
  }
}

Future<void> _validatePackageHeader(
    File archive, TargetPlatform platform) async {
  final file = await archive.open();
  try {
    final header = await file.read(4);
    final valid = platform == TargetPlatform.linux
        ? header.length >= 2 && header[0] == 0x1f && header[1] == 0x8b
        : header.length >= 4 &&
            header[0] == 0x50 &&
            header[1] == 0x4b &&
            header[2] == 0x03 &&
            header[3] == 0x04;
    if (!valid) throw const FormatException('桌面安装包文件头不正确');
  } finally {
    await file.close();
  }
}

Future<Directory> _validateExtractedPayload(
    Directory root, TargetPlatform platform, String version) async {
  final payload = platform == TargetPlatform.macOS
      ? Directory(p.join(root.path, 'MagicChat.app'))
      : root;
  final required = platform == TargetPlatform.windows
      ? [
          'magicchat_client.exe',
          'flutter_windows.dll',
          p.join('data', 'flutter_assets'),
        ]
      : platform == TargetPlatform.macOS
          ? [
              p.join('Contents', 'MacOS', 'MagicChat'),
              p.join('Contents', 'Info.plist'),
              p.join('Contents', 'Frameworks'),
            ]
          : [
              'magicchat_client',
              p.join('data', 'flutter_assets'),
              p.join('lib', 'libflutter_linux_gtk.so'),
            ];
  if (!await payload.exists()) {
    throw FormatException('MagicChat $version 安装包结构不正确');
  }
  for (final relative in required) {
    if (!await FileSystemEntity.isFile(p.join(payload.path, relative)) &&
        !await FileSystemEntity.isDirectory(p.join(payload.path, relative))) {
      throw FormatException('MagicChat $version 安装包缺少 $relative');
    }
  }
  return payload;
}

Future<void> _validateCurrentInstallation(
    Directory target, TargetPlatform platform, String executablePath) async {
  if (p.equals(target.path, p.dirname(target.path))) {
    throw const FormatException('桌面安装目录范围不安全');
  }
  final expectedExecutable =
      p.join(target.path, desktopExecutableRelativePath(platform));
  if (!p.equals(File(expectedExecutable).absolute.path,
      File(executablePath).absolute.path)) {
    throw const FormatException('当前桌面可执行文件不属于安装目录');
  }
  final required = platform == TargetPlatform.windows
      ? ['flutter_windows.dll', p.join('data', 'flutter_assets')]
      : platform == TargetPlatform.macOS
          ? [p.join('Contents', 'Info.plist'), p.join('Contents', 'Frameworks')]
          : [
              p.join('data', 'flutter_assets'),
              p.join('lib', 'libflutter_linux_gtk.so')
            ];
  for (final relative in required) {
    final path = p.join(target.path, relative);
    if (!await FileSystemEntity.isFile(path) &&
        !await FileSystemEntity.isDirectory(path)) {
      throw const FormatException('当前应用不是可安全替换的便携安装');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
