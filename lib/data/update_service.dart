import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum AppUpdatePlatform { android, ios }

extension on AppUpdatePlatform {
  String get manifestKey => switch (this) {
        AppUpdatePlatform.android => 'android',
        AppUpdatePlatform.ios => 'ios',
      };
}

class AppRelease {
  const AppRelease(
      {required this.version, required this.build, required this.url});
  final String version;
  final int build;
  final String url;
}

class UpdateService {
  const UpdateService({http.Client? client, this.platform}) : _client = client;
  final http.Client? _client;
  final AppUpdatePlatform? platform;
  static const manifestUrl = 'https://jiying.chat/releases/version.json';
  static const currentBuild = 1;
  static const currentVersion = '0.1.0';

  Future<AppRelease?> check() async {
    final client = _client ?? http.Client();
    final separator = manifestUrl.contains('?') ? '&' : '?';
    final response = await client.get(
        Uri.parse(
            '$manifestUrl${separator}timestamp=${DateTime.now().millisecondsSinceEpoch}'),
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
    final target = platform ??
        (defaultTargetPlatform == TargetPlatform.iOS
            ? AppUpdatePlatform.ios
            : AppUpdatePlatform.android);
    final releaseConfig = decoded[target.manifestKey];
    if (releaseConfig is! Map<String, dynamic>) {
      throw const FormatException('版本文件缺少移动端配置');
    }
    final version = releaseConfig['version'];
    final build = releaseConfig['build'];
    final url = releaseConfig['url'];
    final buildNumber = build is num &&
            build.isFinite &&
            build == build.truncateToDouble() &&
            build >= 0 &&
            build <= 9007199254740991
        ? build.toInt()
        : null;
    final normalizedVersion = version is String ? version.trim() : '';
    final normalizedUrl = url is String ? url.trim() : '';
    if (version is! String ||
        normalizedVersion.isEmpty ||
        buildNumber == null ||
        normalizedUrl.isEmpty ||
        !normalizedUrl.startsWith('https://')) {
      throw const FormatException('版本文件内容不正确');
    }
    final release = AppRelease(
        version: normalizedVersion, build: buildNumber, url: normalizedUrl);
    return release.build > currentBuild ? release : null;
  }
}
