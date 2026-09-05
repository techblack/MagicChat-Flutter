import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List?> readVoiceRecordingBytes(String path) async {
  if (path.isEmpty) return null;
  final response = await web.window.fetch(path.toJS).toDart;
  if (!response.ok) return null;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

Future<void> deleteVoiceRecordingFile(String path) async {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}
