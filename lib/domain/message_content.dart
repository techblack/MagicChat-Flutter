/// 服务端消息 body 的统一解析结果，未知类型保留原始 JSON 以便向前兼容。
class MessageContent {
  const MessageContent(
      {required this.type, required this.text, this.raw = const {}});
  final String type;
  final String text;
  final Map<String, dynamic> raw;

  /// 服务端撤回消息会省略正文，仅保留 `revoked_at`。
  const MessageContent.revoked()
      : type = 'revoked',
        text = '消息已撤回',
        raw = const {'type': 'revoked'};

  factory MessageContent.parse(Object? value) {
    if (value is! Map<String, dynamic>) {
      return MessageContent(type: 'unknown', text: '$value');
    }
    final type = value['type'];
    final content = value['content'];
    // link/card body 不携带 `content`；即使未来服务端附带该字段，也优先使用
    // 类型摘要，让会话列表和通知在各端保持稳定。
    final text = type == 'link' || type == 'card'
        ? _summary(type, value)
        : content is String
            ? content
            : _summary(type, value);
    return MessageContent(
        type: type is String ? type : 'unknown',
        text: text,
        raw: Map.unmodifiable(value));
  }

  factory MessageContent.fromEnvelope(Object? body, {Object? revokedAt}) {
    return revokedAt is String
        ? const MessageContent.revoked()
        : MessageContent.parse(body);
  }

  static String _summary(Object? type, Map<String, dynamic> body) {
    switch (type) {
      case 'revoked':
        return '消息已撤回';
      case 'image':
        return '[图片]';
      case 'file':
        return '[文件] ${body['name'] ?? ''}'.trim();
      case 'voice':
        return '[语音]';
      case 'choice':
        return '${body['title'] ?? '[选择题]'}';
      case 'link':
        final title = _stringField(body, 'title');
        final url = _stringField(body, 'url');
        return '[链接] ${title.isNotEmpty ? title : url}'.trimRight();
      case 'card':
        final title = _stringField(body, 'title');
        return '[卡片] $title'.trimRight();
      case 'object':
        return '[对象]';
      case 'chart':
        return '[图表]';
      case 'forward_bundle':
        return '[聊天记录] ${body['item_count'] ?? 0} 条';
      default:
        return '[消息]';
    }
  }

  static String _stringField(Map<String, dynamic> body, String key) {
    final value = body[key];
    return value is String ? value.trim() : '';
  }
}

/// 仅允许消息卡片打开 HTTP(S) 外链。
///
/// 服务端会在写入时校验链接，但历史消息和实时事件仍需在客户端再次
/// 验证，避免把 `javascript:`、`data:` 或不完整 URL 交给系统浏览器。
Uri? parseExternalWebUri(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.contains('\\') ||
      RegExp(r'\s').hasMatch(trimmed)) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' ? uri : null;
}

/// 解析应用内卡片可使用的绝对路径；协议相对地址和反斜杠路径不允许进入路由。
String? parseInternalMessagePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.contains('\\') ||
      RegExp(r'\s').hasMatch(trimmed) ||
      !trimmed.startsWith('/') ||
      trimmed.startsWith('//')) {
    return null;
  }
  return trimmed;
}

/// 将服务端提及 token 渲染为用户可读文本，同时保留未知用户的安全占位。
String formatMentionText(
    String content, Iterable<({String id, String name})> contacts) {
  final names = {
    for (final contact in contacts) contact.id.toLowerCase(): contact.name
  };
  return content.replaceAllMapped(RegExp(r'\{\(@(user|app)/([^}]+)\)\}'),
      (match) {
    final type = match.group(1);
    final id = match.group(2)!.toLowerCase();
    if (type == 'user' && id == 'all') return '@所有人';
    final name = names[id];
    return '@${name?.isNotEmpty == true ? name : type == 'app' ? '应用' : '用户'}';
  });
}
