import 'update_installer_types.dart';
import 'update_service.dart';

class DesktopUpdateInstaller implements UpdateInstaller {
  DesktopUpdateInstaller({
    Object? client,
    Object? platform,
    String? executablePath,
    Object? temporaryDirectory,
    Object? archiveValidator,
    Object? archiveExtractor,
    Object? replacementLauncher,
    Object? quit,
  });

  @override
  bool get supported => false;

  @override
  String get progressLabel => '正在下载并校验完整安装包';

  @override
  String get completionHint => '校验完成后将自动替换当前版本并重启。';

  @override
  Future<void> downloadAndInstall(
    AppRelease release, {
    required UpdateDownloadProgress onProgress,
  }) =>
      throw UnsupportedError('当前平台不支持应用内安装更新');

  @override
  Future<void> cancel() async {}
}
