import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/rich_document_paste.dart';
import 'package:magicchat_client/domain/rich_document_format.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

void main() {
  test('富文本粘贴丢弃危险 HTML 并保留安全块和 marks', () {
    final color = richDocumentBlockBackgroundColors[20].value;
    final paste = parseRichDocumentPaste((
      html: '''
        <h5 style="text-align: center">发布标题</h5>
        <p class="source" onclick="alert(1)">
          <span style="font-weight: 700; font-style: italic; text-decoration: underline line-through">格式&nbsp;文本</span>
          <script>alert(1)</script>
          <a href="javascript:alert(2)">危险链接</a>
          <a href="https://example.com/path">安全链接</a>
          <mark data-color="$color">高亮</mark>
        </p>
        <unknown style="font-weight: bold"><strong>保留内容</strong></unknown>
      ''',
      text: '不应使用纯文本回退',
    ));
    final document = _integrate(paste);
    addTearDown(document.destroy);

    expect(paste.blocks.map((block) => block.name),
        ['heading', 'paragraph', 'paragraph']);
    final heading = paste.blocks.first;
    expect(heading.getAttribute('level'), 3);
    expect(heading.getAttribute('textAlign'), 'center');
    final paragraphText = _textNodes(paste.blocks[1]).single;
    expect(paragraphText.toString(), isNot(contains('alert')));
    expect(paragraphText.toString(), contains('格式 文本'));
    final delta = paragraphText.toDelta();
    final formatted = delta
        .firstWhere((operation) => '${operation['insert']}'.contains('格式 文本'));
    expect(formatted['attributes'], containsPair('bold', true));
    expect(formatted['attributes'], containsPair('italic', true));
    expect(formatted['attributes'], containsPair('underline', true));
    expect(formatted['attributes'], containsPair('strike', true));
    final dangerous = delta
        .firstWhere((operation) => '${operation['insert']}'.contains('危险链接'));
    expect(dangerous['attributes'], isNull);
    final safe = delta
        .firstWhere((operation) => '${operation['insert']}'.contains('安全链接'));
    expect((safe['attributes'] as Map)['link'],
        {'href': 'https://example.com/path'});
    final highlighted = delta
        .firstWhere((operation) => '${operation['insert']}'.contains('高亮'));
    expect((highlighted['attributes'] as Map)['highlight'], {'color': color});
    expect(_textNodes(paste.blocks.last).single.toString(), '保留内容');
    expect(_textNodes(paste.blocks.last).single.toDelta().single['attributes'],
        containsPair('bold', true));
  });

  test('富文本粘贴保留任务、表格、分割线和安全图片结构', () {
    final paste = parseRichDocumentPaste((
      html: '''
        <ul data-type="taskList">
          <li data-type="taskItem" data-checked="true">
            <label><input type="checkbox" checked></label>
            <div><p>完成事项</p></div>
          </li>
        </ul>
        <table style="width: 900px"><tbody>
          <tr><td colspan="2" colwidth="120,130"><p>负责人</p></td><td><p>状态</p></td></tr>
          <tr><td><p>小王</p></td><td><p>完成</p></td></tr>
        </tbody></table>
        <hr data-thickness="5" data-line-style="dotted">
        <figure data-document-image data-file-id="file-1" data-width="63" data-alignment="right" data-alt="架构图"><span>旧内容</span></figure>
        <img src="data:image/png;base64,AAAA" alt="危险图片">
      ''',
      text: null,
    ));
    final document = _integrate(paste);
    addTearDown(document.destroy);

    expect(paste.blocks.map((block) => block.name),
        ['taskList', 'table', 'horizontalRule', 'documentImage']);
    final task = paste.blocks.first.toArray().single as yjs.YXmlElement;
    expect(task.name, 'taskItem');
    expect(task.getAttribute('checked'), isTrue);
    expect(_textNodes(task).single.toString(), '完成事项');
    final table = paste.blocks[1];
    final rows = table.toArray().whereType<yjs.YXmlElement>().toList();
    expect(rows, hasLength(2));
    final header = rows.first.toArray().whereType<yjs.YXmlElement>().first;
    expect(header.name, 'tableHeader');
    expect(header.getAttribute('colspan'), 2);
    expect(header.getAttribute('colwidth'), [120, 130]);
    expect(rows.last.toArray().whereType<yjs.YXmlElement>().first.name,
        'tableCell');
    expect(paste.blocks[2].getAttribute('lineStyle'), 'dotted');
    expect(paste.blocks[2].getAttribute('thickness'), 5);
    expect(paste.blocks[3].getAttribute('fileId'), 'file-1');
    expect(paste.blocks[3].getAttribute('alignment'), 'right');
    expect(paste.blocks[3].getAttribute('width'), 65);
    expect(paste.blocks[3].getAttribute('alt'), '架构图');
    expect(paste.blocks.join(), isNot(contains('危险图片')));
  });

  test('剪贴板无 HTML 时按段落粘贴且疑似 HTML 不作为源码文本', () {
    final plain = parseRichDocumentPaste((html: null, text: '第一段\n第二段'));
    final plainDocument = _integrate(plain);
    addTearDown(plainDocument.destroy);
    expect(plain.blocks.map((block) => block.name), ['paragraph', 'paragraph']);
    expect(plain.blocks.map((block) => _textNodes(block).single.toString()),
        ['第一段', '第二段']);

    final htmlSource = parseRichDocumentPaste(
        (html: null, text: '<p>结构正文</p><script>危险源码</script>'));
    final htmlDocument = _integrate(htmlSource);
    addTearDown(htmlDocument.destroy);
    expect(htmlSource.blocks.map((block) => block.name), ['paragraph']);
    expect(_textNodes(htmlSource.blocks.single).single.toString(), '结构正文');
  });

  test('非矩形表格降级保留单元格正文而不写入不可渲染表格', () {
    final paste = parseRichDocumentPaste((
      html: '''
        <table>
          <tr><td><strong>A</strong></td><td>B</td></tr>
          <tr><td>C</td></tr>
        </table>
      ''',
      text: null,
    ));
    final document = _integrate(paste);
    addTearDown(document.destroy);

    expect(paste.blocks.map((block) => block.name),
        ['paragraph', 'paragraph', 'paragraph']);
    expect(paste.blocks.map((block) => _textNodes(block).single.toString()),
        ['A', 'B', 'C']);
    expect(_textNodes(paste.blocks.first).single.toDelta().single['attributes'],
        containsPair('bold', true));
  });
}

yjs.Doc _integrate(RichDocumentPaste paste) {
  final document = yjs.Doc();
  final body = document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
  body.insert(0, paste.blocks);
  return document;
}

List<yjs.YXmlText> _textNodes(yjs.YXmlFragment node) {
  final result = <yjs.YXmlText>[];
  for (final child in node.toArray()) {
    if (child is yjs.YXmlText) {
      result.add(child);
    } else if (child is yjs.YXmlFragment) {
      result.addAll(_textNodes(child));
    }
  }
  return result;
}
