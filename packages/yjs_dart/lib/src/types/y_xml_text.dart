library;

import 'abstract_type.dart';
import 'y_text.dart';
import '../utils/doc.dart';
import '../structs/item.dart';

/// A shared XML text node. Its wire representation is Yjs type reference 6.
class YXmlText extends YText {
  String? _prelimText;
  Map<String, Object?>? _prelimAttributes;

  YXmlText() : super() {
    legacyTypeRef = typeRefXmlText;
  }

  @override
  void integrate(Doc doc, Item? item) {
    super.integrate(doc, item);
    final text = _prelimText;
    _prelimText = null;
    if (text != null && text.isNotEmpty) {
      insert(0, text, _prelimAttributes);
    }
    _prelimAttributes = null;
  }

  @override
  void insert(int index, String text, [Map<String, Object?>? attributes]) {
    if (doc == null) {
      if (index != 0 && index != (_prelimText?.length ?? 0)) {
        throw RangeError('Length exceeded!');
      }
      _prelimText = index == 0 ? text : '${_prelimText ?? ''}$text';
      _prelimAttributes = attributes;
      return;
    }
    super.insert(index, text, attributes);
  }

  @override
  YXmlText clone() {
    final newType = YXmlText();
    newType._prelimText = toString();
    return newType;
  }
}
