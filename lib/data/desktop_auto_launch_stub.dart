import 'desktop_auto_launch_types.dart';

class DesktopAutoLaunchService implements DesktopAutoLaunchController {
  const DesktopAutoLaunchService(
      {Object? platform,
      String? executablePath,
      String? homeDirectory,
      Map<String, String>? environment,
      Object? processRunner});

  @override
  bool get isSupported => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {
    throw const DesktopAutoLaunchException('当前平台不支持开机自动启动');
  }

  Future<String> registrationPath() async {
    throw const DesktopAutoLaunchException('当前平台不支持开机自动启动');
  }
}
