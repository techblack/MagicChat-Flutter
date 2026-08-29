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
        final caption = _stringField(body, 'caption');
        return caption.isEmpty ? '[图片]' : '[图片] $caption';
      case 'file':
        return '[文件] ${body['name'] ?? ''}'.trim();
      case 'voice':
        final duration = body['duration_ms'];
        final transcript = _stringField(body, 'transcript');
        final durationText = duration is num && duration > 0
            ? ' ${_formatDuration(duration.toInt())}'
            : '';
        return '[语音]$durationText${transcript.isEmpty ? '' : ' - $transcript'}';
      case 'choice':
        final content = _stringField(body, 'content');
        return content.isEmpty ? '[选择题]' : '[选择题] $content';
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
        final title = _stringField(body, 'title');
        return title.isEmpty ? '[图表]' : '[图表] $title';
      case 'forward_bundle':
        return '[聊天记录] ${body['item_count'] ?? 0} 条';
      case 'system_event':
        return _systemEventSummary(body);
      case 'unsupported':
        return '暂不支持查看该消息';
      default:
        return '[消息]';
    }
  }

  /// 系统事件不携带普通消息的 `content`，但各端仍需在会话中显示可读的
  /// 操作摘要。服务端事件字段保持原样存入 [raw]，这里只做展示层映射，
  /// 对未知事件回退到稳定占位，避免历史消息解析失败。
  static String _systemEventSummary(Map<String, dynamic> body) {
    final event = body['event'];
    final actor = _systemUserName(body['actor']);
    switch (event) {
      case 'friendship_created':
        return '你们已成为好友，现在可以开始聊天了';
      case 'message_revoked':
        return '$actor 撤回了一条消息';
      case 'topic_closed':
        return '$actor 已将话题关闭';
      case 'group_avatar_updated':
        return '$actor 修改了群头像';
      case 'group_visibility_changed':
        return body['visibility'] == 'public'
            ? '$actor 将当前群设置为公开群'
            : '$actor 将当前群设为私有群';
      case 'group_member_joined':
        return '$actor 加入群聊';
      case 'group_member_left':
        return '$actor 已退出群聊';
      case 'group_member_removed':
        final target = _systemUserName(body['target']);
        return '$actor 已将 $target 移出群聊';
      case 'group_name_updated':
        return '$actor 修改群聊名称为 ${_stringField(body, 'name')}';
      case 'group_announcement_updated':
        return _stringField(body, 'announcement').isNotEmpty
            ? '$actor 更新了群公告'
            : '$actor 清空了群公告';
      case 'group_members_invited':
        final invitees = body['invitees'];
        if (invitees is List) {
          final names = invitees
              .map(_systemUserName)
              .where((name) => name.isNotEmpty)
              .join(', ');
          if (names.isNotEmpty) {
            return '${_systemUserName(body['inviter'])} 邀请 $names 加入群聊';
          }
        }
        return '${_systemUserName(body['inviter'])} 邀请成员加入群聊';
      default:
        return '[系统消息]';
    }
  }

  static String _systemUserName(Object? value) {
    if (value is Map<String, dynamic>) {
      final displayName = value['display_name'];
      if (displayName is String && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }
      final name = value['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    }
    return '用户';
  }

  static String _stringField(Map<String, dynamic> body, String key) {
    final value = body[key];
    return value is String ? value.trim() : '';
  }

  static String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).ceil();
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
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

/// 解析 Markdown 渲染器提供的链接值。
///
/// Markdown 的 `href` 可以为空（例如引用定义缺失）或不是字符串；统一
/// 走 [parseExternalWebUri]，避免渲染器回调绕过外链协议校验。
Uri? parseMarkdownLink(Object? href) {
  return href is String ? parseExternalWebUri(href) : null;
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
