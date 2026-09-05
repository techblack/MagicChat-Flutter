enum StoragePart { media, messages, all }

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
