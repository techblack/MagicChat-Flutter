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
