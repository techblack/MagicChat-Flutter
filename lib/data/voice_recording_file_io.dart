import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readVoiceRecordingBytes(String path) async {
  final file = File(path);
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> deleteVoiceRecordingFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
