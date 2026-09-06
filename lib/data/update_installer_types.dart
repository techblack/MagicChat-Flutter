import 'update_service.dart';

typedef UpdateDownloadProgress = void Function(double value);
typedef UpdatePackageOpener = Future<bool> Function(String filePath);

abstract interface class UpdateInstaller {
  bool get supported;

  String get progressLabel;

  String get completionHint;

  Future<void> downloadAndInstall(
    AppRelease release, {
    required UpdateDownloadProgress onProgress,
  });

  Future<void> cancel();
}

class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();

  @override
  String toString() => '安装包下载已取消';
}

class UpdateInstallBlockedByActiveTransfers implements Exception {
  const UpdateInstallBlockedByActiveTransfers();

  @override
  String toString() => '仍有文件正在上传或下载，请等待完成或取消传输后重试';
}
