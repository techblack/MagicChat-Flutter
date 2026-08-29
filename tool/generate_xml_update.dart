import 'dart:io';

import 'package:yjs_dart/yjs_dart.dart' as yjs;

void main(List<String> args) {
  final output = args.isEmpty ? '/tmp/magicchat-flutter-body.yjs' : args.first;
  final document = yjs.Doc(yjs.DocOpts(clientID: 42, guid: 'flutter-fixture'));
  final body = document.get<yjs.YXmlFragment>('body', yjs.YXmlFragment.new)!;
  final paragraph = yjs.YXmlElement('paragraph');
  body.insert(0, [paragraph]);
  final text = yjs.YXmlText();
  paragraph.insert(0, [text]);
  text.insert(0, 'Flutter XML 正文');
  File(output).writeAsBytesSync(yjs.encodeStateAsUpdate(document));
  document.destroy();
}
