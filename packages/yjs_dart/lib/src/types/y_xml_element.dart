library;

import 'y_xml_fragment.dart';
import 'abstract_type.dart';

/// A shared XML element. Its wire representation is Yjs type reference 3.
class YXmlElement extends YXmlFragment {
  YXmlElement(String name, [int wireType = typeRefXmlElement]) : super(name) {
    legacyTypeRef = wireType;
  }

  @override
  YXmlElement clone() {
    final newType = YXmlElement(name ?? '', legacyTypeRef);
    for (final entry in typeMapGetAll(this).entries) {
      newType.setAttribute(entry.key, entry.value);
    }
    newType.insert(
      0,
      toArray()
          .map((value) => value is AbstractType ? value.clone() : value)
          .toList(),
    );
    return newType;
  }
}
