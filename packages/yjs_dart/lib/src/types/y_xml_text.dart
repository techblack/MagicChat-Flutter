library;

import 'abstract_type.dart';
import 'y_text.dart';
import '../utils/doc.dart';
import '../structs/item.dart';

/// A shared XML text node. Its wire representation is Yjs type reference 6.
class YXmlText extends YText {
  final List<_PrelimXmlTextSegment> _prelimSegments = [];

  YXmlText() : super() {
    legacyTypeRef = typeRefXmlText;
  }

  @override
  void integrate(Doc doc, Item? item) {
    super.integrate(doc, item);
    final segments = List<_PrelimXmlTextSegment>.of(_prelimSegments);
    _prelimSegments.clear();
    for (final segment in segments) {
      super.insert(length, segment.text, segment.attributes);
    }
  }

  @override
  void insert(int index, String text, [Map<String, Object?>? attributes]) {
    if (doc == null) {
      final currentLength = _prelimSegments.fold<int>(
          0, (length, segment) => length + segment.text.length);
      if (index != 0 && index != currentLength) {
        throw RangeError('Length exceeded!');
      }
      final segment = _PrelimXmlTextSegment(
          text, attributes == null ? null : Map.of(attributes));
      if (index == 0) {
        _prelimSegments.insert(0, segment);
      } else {
        _prelimSegments.add(segment);
      }
      return;
    }
    super.insert(index, text, attributes);
  }

  @override
  int get length => doc == null
      ? _prelimSegments.fold<int>(
          0, (length, segment) => length + segment.text.length)
      : super.length;

  @override
  String toString() => doc == null
      ? _prelimSegments.map((segment) => segment.text).join()
      : super.toString();

  @override
  YXmlText clone() {
    final newType = YXmlText();
    if (doc == null) {
      for (final segment in _prelimSegments) {
        newType.insert(newType.length, segment.text, segment.attributes);
      }
    } else {
      newType.insert(0, toString());
    }
    return newType;
  }
}

class _PrelimXmlTextSegment {
  const _PrelimXmlTextSegment(this.text, this.attributes);

  final String text;
  final Map<String, Object?>? attributes;
}
