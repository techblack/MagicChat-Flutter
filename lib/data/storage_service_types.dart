enum StoragePart { media, messages, all }

class StorageClearResult {
  const StorageClearResult({this.cleared = const {}, this.failed = const {}});

  final Set<StoragePart> cleared;
  final Set<StoragePart> failed;

  bool get succeeded => failed.isEmpty;
  bool get partiallySucceeded => cleared.isNotEmpty && failed.isNotEmpty;
}

class StorageInfo {
  const StorageInfo({required this.mediaBytes, required this.messageBytes});

  final int mediaBytes;
  final int messageBytes;

  int get totalBytes => mediaBytes + messageBytes;

  String get formattedMedia => formatStorageSize(mediaBytes);
  String get formattedMessages => formatStorageSize(messageBytes);
  String get formattedTotal => formatStorageSize(totalBytes);
}

String formatStorageSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
