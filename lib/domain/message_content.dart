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
    final text = content is String ? content : _summary(type, value);
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
