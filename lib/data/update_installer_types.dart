typedef UpdateDownloadProgress = void Function(double value);
typedef UpdatePackageOpener = Future<bool> Function(String filePath);

class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();

  @override
  String toString() => '安装包下载已取消';
}
