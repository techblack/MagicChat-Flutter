enum QrContentKind { text, web }

class QrContentClassification {
  const QrContentClassification.text(this.value) : kind = QrContentKind.text;
  const QrContentClassification.web(this.value) : kind = QrContentKind.web;

  final QrContentKind kind;
  final String value;
}

QrContentClassification classifyQrContent(String content) {
  final candidate = content.trim();
  final uri = Uri.tryParse(candidate);
  if (uri != null &&
      uri.host.isNotEmpty &&
      (uri.scheme.toLowerCase() == 'http' ||
          uri.scheme.toLowerCase() == 'https')) {
    return QrContentClassification.web(uri.toString());
  }
  return QrContentClassification.text(content);
}

bool isAllowedQrWebUri(Uri uri) =>
    uri.host.isNotEmpty &&
    (uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https');
