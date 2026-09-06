import 'update_installer_types.dart';
import 'update_service.dart';

class AndroidUpdateInstaller {
  AndroidUpdateInstaller({
    Object? client,
    Object? platform,
    Object? temporaryDirectory,
    UpdatePackageOpener? packageOpener,
  });

  bool get supported => false;

  Future<void> downloadAndInstall(
    AppRelease release, {
    required UpdateDownloadProgress onProgress,
  }) =>
      throw UnsupportedError('当前平台不支持应用内安装更新');

  Future<void> cancel() async {}
}
