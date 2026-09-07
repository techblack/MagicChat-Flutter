import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
  });

  static const unavailable = AppVersionInfo(version: '0.0.0', buildNumber: 0);

  final String version;
  final int buildNumber;

  String get versionWithBuild => '$version+$buildNumber';

  static Future<AppVersionInfo> load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: packageInfo.version,
      buildNumber: int.parse(packageInfo.buildNumber),
    );
  }
}
