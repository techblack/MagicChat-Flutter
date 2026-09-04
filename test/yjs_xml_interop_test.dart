import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart' as yjs;

void main() {
  test('可解码 Desktop Tiptap body XML fixture 并保留 block/text 属性', () {
    final fixture = File('test/fixtures/web-composite-document-state.yjs')
        .readAsBytesSync();
    final document = yjs.Doc(yjs.DocOpts(guid: 'web-fixture'));
    final body = document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;

    yjs.applyUpdate(document, Uint8List.fromList(fixture));

    expect(body.toString(), contains('可编辑基础段落'));
    expect(body.toString(), contains('完成事项'));
    expect(body.toString(), contains('file-fixture-1'));
    final first = body.toArray().whereType<yjs.YXmlElement>().first;
    expect(first.name, 'paragraph');
    expect(
        first.toArray().whereType<yjs.YXmlText>().single.toString(), '可编辑基础段落');
    final image = _findElement(body, 'documentImage');
    expect(image?.getAttribute('fileId'), 'file-fixture-1');
    expect(image?.getAttribute('alignment'), 'right');
    final task = _findElement(body, 'taskItem');
    expect(task?.getAttribute('checked'), true);
    expect(yjs.encodeStateAsUpdate(document), orderedEquals(fixture));
    document.destroy();
  });
}

yjs.YXmlElement? _findElement(yjs.YXmlFragment parent, String name) {
  for (final child in parent.toArray()) {
    if (child is yjs.YXmlElement) {
      if (child.name == name) return child;
      final nested = _findElement(child, name);
      if (nested != null) return nested;
    }
  }
  return null;
}
