import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models.dart';

String documentExportFileName(ProjectDocument document) {
  final raw = document.title.trim();
  final safe = raw
      .replaceAll(RegExp(r'''[\\/:*?"<>|]'''), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final base = safe.isEmpty ? 'document' : safe;
  return '$base.${document.documentType == 'markdown' ? 'md' : 'txt'}';
}

String documentExportText({required String title, required String body}) {
  final normalizedTitle = title.trim();
  final normalizedBody = body.trimRight();
  if (normalizedTitle.isEmpty) return normalizedBody;
  if (normalizedBody.isEmpty) return '# $normalizedTitle';
  return '# $normalizedTitle\n\n$normalizedBody';
}

Uint8List documentExportBytes({required String title, required String body}) =>
    Uint8List.fromList(
        utf8.encode(documentExportText(title: title, body: body)));
