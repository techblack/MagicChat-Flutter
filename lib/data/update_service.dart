import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum AppUpdatePlatform { android, ios, windows, macos, linux }

extension on AppUpdatePlatform {
  String get manifestKey => switch (this) {
        AppUpdatePlatform.android => 'android',
        AppUpdatePlatform.ios => 'ios',
        AppUpdatePlatform.windows => 'windows',
        AppUpdatePlatform.macos => 'macos',
        AppUpdatePlatform.linux => 'linux',
      };
}

bool _isDesktopPlatform(AppUpdatePlatform platform) =>
    platform == AppUpdatePlatform.windows ||
    platform == AppUpdatePlatform.macos ||
    platform == AppUpdatePlatform.linux;

String _desktopAssetName(AppUpdatePlatform platform) => switch (platform) {
      AppUpdatePlatform.windows => 'MagicChat-Windows-x64.zip',
      AppUpdatePlatform.macos => 'MagicChat-macOS.zip',
      AppUpdatePlatform.linux => 'MagicChat-Linux-x64.tar.gz',
      _ => '',
    };

class AppRelease {
  const AppRelease(
      {required this.version,
      required this.build,
      required this.url,
      this.assetName,
      this.size,
      this.sha256,
      this.sha256Url});
  final String version;
  final int build;
  final String url;
  final String? assetName;
  final int? size;
  final String? sha256;
  final String? sha256Url;
}

class UpdateService {
  const UpdateService({http.Client? client, this.platform}) : _client = client;
  final http.Client? _client;
  final AppUpdatePlatform? platform;
  static const releaseManifestUrl = 'https://jiying.chat/releases/version.json';
  static const desktopReleaseApiUrl =
      'https://api.github.com/repos/techblack/MagicChat-Flutter/releases/latest';

  /// 更新源可在编译时替换为完整 HTTPS manifest URL；默认使用 release 源。
  static const updateSource = String.fromEnvironment('MAGICCHAT_UPDATE_SOURCE',
      defaultValue:
          String.fromEnvironment('UPDATE_SOURCE', defaultValue: 'release'));
  static const currentBuild = 27;
  static const currentVersion = '0.3.14';

  static String get manifestUrl =>
      updateSource == 'release' ? releaseManifestUrl : updateSource;

  Future<AppRelease?> check() async {
    final client = _client ?? http.Client();
    final target = platform ?? _defaultPlatform();
    if (updateSource == 'release' && _isDesktopPlatform(target)) {
      return _checkDesktop(client, target);
    }
    final source = Uri.tryParse(manifestUrl);
    if (source == null || source.scheme != 'https' || source.host.isEmpty) {
      throw const FormatException('更新源必须是有效的 HTTPS 地址');
    }
    final response = await client.get(
        source.replace(queryParameters: {
          ...source.queryParameters,
          'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
        }),
        headers: {
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('版本服务返回 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('版本文件格式不正确');
    }
    final releaseConfig = decoded[target.manifestKey];
    if (releaseConfig is! Map<String, dynamic>) {
      throw const FormatException('版本文件缺少移动端配置');
    }
    final version = releaseConfig['version'];
    final build = releaseConfig['build'];
    final url = releaseConfig['url'];
    final size = releaseConfig['size'];
    final sha256Value = releaseConfig['sha256'];
    final sha256UrlValue = releaseConfig['sha256_url'];
    final buildNumber = build is num &&
            build.isFinite &&
            build == build.truncateToDouble() &&
            build >= 0 &&
            build <= 9007199254740991
        ? build.toInt()
        : null;
    final normalizedVersion = version is String ? version.trim() : '';
    final normalizedUrl = url is String ? url.trim() : '';
    final normalizedSha256 =
        sha256Value is String ? sha256Value.trim().toLowerCase() : null;
    final normalizedSha256Url =
        sha256UrlValue is String ? sha256UrlValue.trim() : null;
    final sizeNumber = size is num &&
            size.isFinite &&
            size == size.truncateToDouble() &&
            size > 0
        ? size.toInt()
        : null;
    if (version is! String ||
        normalizedVersion.isEmpty ||
        buildNumber == null ||
        normalizedUrl.isEmpty ||
        !normalizedUrl.startsWith('https://') ||
        (size != null && sizeNumber == null) ||
        (normalizedSha256 != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedSha256)) ||
        (normalizedSha256Url != null &&
            !normalizedSha256Url.startsWith('https://'))) {
      throw const FormatException('版本文件内容不正确');
    }
    final urlSegments = Uri.parse(normalizedUrl).pathSegments;
    final release = AppRelease(
        version: normalizedVersion,
        build: buildNumber,
        url: normalizedUrl,
        assetName: urlSegments.isEmpty ? null : urlSegments.last,
        size: sizeNumber,
        sha256: normalizedSha256,
        sha256Url: normalizedSha256Url);
    return release.build > currentBuild ? release : null;
  }

  AppUpdatePlatform _defaultPlatform() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => AppUpdatePlatform.ios,
        TargetPlatform.windows => AppUpdatePlatform.windows,
        TargetPlatform.macOS => AppUpdatePlatform.macos,
        TargetPlatform.linux => AppUpdatePlatform.linux,
        _ => AppUpdatePlatform.android,
      };

  Future<AppRelease?> _checkDesktop(
      http.Client client, AppUpdatePlatform target) async {
    final response =
        await client.get(Uri.parse(desktopReleaseApiUrl), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'MagicChat-Flutter',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('版本服务返回 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('桌面版本响应格式不正确');
    }
    final tag = decoded['tag_name'];
    final version = tag is String && tag.trim().startsWith('v')
        ? tag.trim().substring(1)
        : '';
    final assetName = _desktopAssetName(target);
    final assets = decoded['assets'];
    if (version.isEmpty || !_isStableVersion(version) || assets is! List) {
      throw const FormatException('桌面版本响应格式不正确');
    }
    Map<String, dynamic>? asset;
    Map<String, dynamic>? checksums;
    for (final value in assets) {
      if (value is Map && value['name'] == assetName) {
        asset = Map<String, dynamic>.from(value);
      }
      if (value is Map && value['name'] == 'SHA256SUMS.txt') {
        checksums = Map<String, dynamic>.from(value);
      }
    }
    final url = asset?['browser_download_url'];
    final size = asset?['size'];
    final checksumUrl = checksums?['browser_download_url'];
    if (url is! String || !url.trim().startsWith('https://')) {
      throw const FormatException('桌面版本缺少有效下载地址');
    }
    final sizeNumber = size is num &&
            size.isFinite &&
            size == size.truncateToDouble() &&
            size > 0
        ? size.toInt()
        : null;
    if (size != null && sizeNumber == null) {
      throw const FormatException('桌面版本安装包大小不正确');
    }
    if (checksumUrl != null &&
        (checksumUrl is! String ||
            !checksumUrl.trim().startsWith('https://'))) {
      throw const FormatException('桌面版本校验文件地址不正确');
    }
    if (_compareVersions(version, currentVersion) <= 0) return null;
    return AppRelease(
        version: version,
        build: _versionBuild(version),
        url: url.trim(),
        assetName: assetName,
        size: sizeNumber,
        sha256Url: checksumUrl is String ? checksumUrl.trim() : null);
  }

  bool _isStableVersion(String value) =>
      RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value);

  int _compareVersions(String left, String right) {
    List<int> parts(String value) => value
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
    final a = parts(left);
    final b = parts(right);
    for (var index = 0; index < 3; index++) {
      final result = a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    return 0;
  }

  int _versionBuild(String value) {
    final parts = value.split('.').map(int.parse).toList(growable: false);
    return parts[0] * 1000000 + parts[1] * 1000 + parts[2];
  }
}
