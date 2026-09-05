import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/domain/message_content.dart';

void main() {
  test('结构化消息生成稳定摘要并保留原始字段', () {
    final image = MessageContent.parse({'type': 'image', 'file_id': 'f1'});
    expect(image.type, 'image');
    expect(image.text, '[图片]');
    expect(image.raw['file_id'], 'f1');
    expect(MessageContent.parse({'type': 'chart'}).text, '[图表]');
  });

  test('链接和卡片使用类型摘要并保留完整 raw body', () {
    final link = MessageContent.parse({
      'type': 'link',
      'title': 'Example Docs',
      'url': 'https://example.com/docs',
      'content': '不应覆盖链接摘要',
    });
    final card = MessageContent.parse({
      'type': 'card',
      'title': '任务动态',
      'description': '状态：待办',
      'url': '/projects/one',
    });

    expect(link.text, '[链接] Example Docs');
    expect(link.raw['url'], 'https://example.com/docs');
    expect(link.raw['content'], '不应覆盖链接摘要');
    expect(card.text, '[卡片] 任务动态');
    expect(card.raw['description'], '状态：待办');
  });

  test('链接摘要在标题缺失时回退到 URL', () {
    final link = MessageContent.parse(
        {'type': 'link', 'url': 'https://example.com/fallback'});
    expect(link.text, '[链接] https://example.com/fallback');
  });

  test('文档卡片路径只接受可编辑文档类型并解析编码后的标识', () {
    expect(parseDocumentMessagePath('/documents/markdown/document%2F1'),
        (documentType: 'markdown', documentId: 'document/1'));
    expect(parseDocumentMessagePath('/documents/folder/document-1'), isNull);
    expect(parseDocumentMessagePath('https://example.com/documents/document/1'),
        isNull);
  });

  test('消息摘要覆盖图片说明、语音时长和未知类型', () {
    expect(
      MessageContent.parse({
        'type': 'image',
        'file_id': 'f1',
        'caption': '现场照片',
      }).text,
      '[图片] 现场照片',
    );
    expect(
      MessageContent.parse({
        'type': 'voice',
        'duration_ms': 42800,
        'transcript': '会议开始',
      }).text,
      '[语音] 00:43 - 会议开始',
    );
    expect(
      MessageContent.parse({'type': 'unsupported'}).text,
      '暂不支持查看该消息',
    );
  });

  test('外链解析仅接受带主机的 HTTP(S) 地址', () {
    expect(parseExternalWebUri('https://example.com/path')?.scheme, 'https');
    expect(parseExternalWebUri('HTTP://example.com/path')?.scheme, 'http');
    for (final value in [
      'javascript:alert(1)',
      'data:text/html,test',
      'https:example.com/path',
      '//example.com/path',
      'https://example.com/a b',
      r'https://example.com/a\b',
    ]) {
      expect(parseExternalWebUri(value), isNull, reason: value);
    }
  });

  test('Markdown 链接复用外链协议校验', () {
    expect(parseMarkdownLink('https://example.com/docs')?.host, 'example.com');
    expect(parseMarkdownLink('javascript:alert(1)'), isNull);
    expect(parseMarkdownLink(null), isNull);
  });

  test('应用内卡片仅接受单斜杠绝对路径', () {
    expect(parseInternalMessagePath(' /projects/one?taskId=task-1 '),
        '/projects/one?taskId=task-1');
    expect(parseInternalMessagePath('//evil.example/path'), isNull);
    expect(parseInternalMessagePath(r'/projects/one\task'), isNull);
  });

  test('撤回消息正文缺失时使用稳定占位文案', () {
    final content =
        MessageContent.fromEnvelope(null, revokedAt: '2026-08-29T12:00:00Z');
    expect(content.type, 'revoked');
    expect(content.text, '消息已撤回');
    expect(content.raw['type'], 'revoked');
  });

  test('正文明确标记 revoked 时也使用撤回占位文案', () {
    final content = MessageContent.parse({'type': 'revoked'});
    expect(content.type, 'revoked');
    expect(content.text, '消息已撤回');
  });

  test('系统事件生成与其他客户端一致的操作摘要', () {
    expect(
      MessageContent.parse({
        'type': 'system_event',
        'event': 'group_member_removed',
        'actor': {'id': 'u1', 'display_name': 'Alice'},
        'target': {'id': 'u2', 'display_name': 'Bob'},
      }).text,
      'Alice 已将 Bob 移出群聊',
    );
    expect(
      MessageContent.parse({
        'type': 'system_event',
        'event': 'group_members_invited',
        'inviter': {'id': 'u1', 'display_name': 'Alice'},
        'invitees': [
          {'id': 'u2', 'display_name': 'Bob'},
          {'id': 'u3', 'display_name': 'Carol'},
        ],
      }).text,
      'Alice 邀请 Bob, Carol 加入群聊',
    );
    expect(
      MessageContent.parse({
        'type': 'system_event',
        'event': 'friendship_created',
      }).text,
      '你们已成为好友，现在可以开始聊天了',
    );
  });

  test('未知系统事件保留稳定占位摘要', () {
    expect(
      MessageContent.parse({'type': 'system_event', 'event': 'future_event'})
          .text,
      '[系统消息]',
    );
  });

  test('提及 token 按联系人名称渲染', () {
    expect(
      formatMentionText(
        '你好 {(@user/ABC)} {(@user/all)} {(@app/XYZ)}',
        [(id: 'abc', name: '小明')],
      ),
      '你好 @小明 @所有人 @应用',
    );
  });
}
