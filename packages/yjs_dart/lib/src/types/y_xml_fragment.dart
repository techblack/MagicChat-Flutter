library;

import '../utils/transaction.dart';
import '../utils/doc.dart';
import '../structs/item.dart';
import 'abstract_type.dart';
import 'y_xml_text.dart';

// for typeListSlice

/// A shared XML Fragment.
///
/// Mirrors: `YXmlFragment` in yjs/src/xml/xml-fragment.js
class YXmlFragment extends AbstractType<dynamic> {
  final List<Object?> _prelimContent = [];
  final Map<String, Object?> _prelimAttributes = {};

  YXmlFragment([String? name]) : super(name);

  @override
  void integrate(Doc doc, Item? item) {
    super.integrate(doc, item);
    if (_prelimAttributes.isNotEmpty) {
      final attributes = Map<String, Object?>.from(_prelimAttributes);
      _prelimAttributes.clear();
      attributes.forEach(setAttribute);
    }
    if (_prelimContent.isNotEmpty) {
      final content = List<Object?>.from(_prelimContent);
      _prelimContent.clear();
      insert(0, content);
    }
  }

  /// Sets or updates an attribute.
  void setAttribute(String key, Object? value) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeMapSet(tr, this, key, value);
      });
    } else {
      _prelimAttributes[key] = value;
    }
  }

  /// Returns the attribute value for [key], or null if not set.
  Object? getAttribute(String key) {
    return typeMapGet(this, key);
  }

  /// Inserts content at [index].
  void insert(int index, List<Object?> content) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListInsertGenerics(tr, this, index, content);
      });
    } else {
      _prelimContent.insertAll(index, content);
    }
  }

  /// Deletes [length] XML children starting at [index].
  void delete(int index, [int length = 1]) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListDelete(tr, this, index, length);
      });
    } else {
      warnPrematureAccess();
    }
  }

  /// Returns the list content as a List.
  List<Object?> toArray() {
    return typeListSlice(this, 0, length);
  }

  @override
  YXmlFragment clone() {
    final newType = YXmlFragment(name);
    // Clone children
    newType.insert(
      0,
      toArray().map((c) => c is AbstractType ? c.clone() : c).toList(),
    );
    // Clone attributes
    // Accessing internal map requires helper?
    // we can use typeMapGetAll
    final attrs = typeMapGetAll(this);
    attrs.forEach((k, v) {
      newType.setAttribute(k, v);
    });
    return newType;
  }

  @override
  String toJson() => toString();

  @override
  String toString() {
    final content = toArray().map(_xmlValue).join();
    if (name == null) return content;
    final attributes = typeMapGetAll(this)
        .entries
        .map((entry) => ' ${entry.key}="${_escapeXml('${entry.value ?? ''}')}"')
        .join();
    return '<$name$attributes>$content</$name>';
  }
}

String _xmlValue(Object? value) {
  if (value is YXmlFragment) return value.toString();
  if (value is YXmlText) return _escapeXml(value.toString());
  if (value is AbstractType<dynamic>) return _escapeXml(value.toString());
  return _escapeXml('$value');
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
