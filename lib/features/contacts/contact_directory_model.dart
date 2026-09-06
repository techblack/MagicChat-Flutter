import 'package:pinyin/pinyin.dart';

import '../../domain/models.dart';

enum ContactDirectoryCategory {
  newFriends,
  myApps,
  allApps,
  joinedGroups,
  publicGroups,
}

extension ContactDirectoryCategoryLabel on ContactDirectoryCategory {
  String get label => switch (this) {
        ContactDirectoryCategory.newFriends => '新朋友',
        ContactDirectoryCategory.myApps => '我的应用',
        ContactDirectoryCategory.allApps => '所有应用',
        ContactDirectoryCategory.joinedGroups => '我加入的群组',
        ContactDirectoryCategory.publicGroups => '公开群组',
      };
}

const contactIndexLabels = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
  '#',
];

class ContactDirectorySection {
  const ContactDirectorySection({required this.label, required this.contacts});

  final String label;
  final List<Contact> contacts;
}

List<ContactDirectorySection> buildContactSections(Iterable<Contact> contacts) {
  final users =
      contacts.where((item) => item.type == 'user').toList(growable: false);
  final grouped = <String, List<Contact>>{};
  for (final contact in users) {
    grouped
        .putIfAbsent(contactIndexLabel(contact.displayName), () => [])
        .add(contact);
  }
  final sortKeys = <String, String>{
    for (final contact in users)
      contact.id: _contactSortKey(contact.displayName),
  };
  for (final values in grouped.values) {
    values.sort((left, right) {
      final byName =
          (sortKeys[left.id] ?? '').compareTo(sortKeys[right.id] ?? '');
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
  }
  return [
    for (final label in contactIndexLabels)
      if (grouped[label]?.isNotEmpty == true)
        ContactDirectorySection(label: label, contacts: grouped[label]!),
  ];
}

String contactIndexLabel(String name) {
  final key = _contactSortKey(name);
  if (key.isEmpty) return '#';
  final first = String.fromCharCode(key.runes.first);
  final initial = _latinInitial(first) ?? first.toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(initial) ? initial : '#';
}

List<Contact> contactsForCategory(ContactDirectoryCategory category,
    Iterable<Contact> contacts, String currentUserId) {
  final normalizedUserId = currentUserId.trim().toLowerCase();
  final values = contacts.where((contact) {
    return switch (category) {
      ContactDirectoryCategory.newFriends => false,
      ContactDirectoryCategory.myApps => contact.type == 'app' &&
          contact.creatorUserId?.trim().toLowerCase() == normalizedUserId &&
          normalizedUserId.isNotEmpty,
      ContactDirectoryCategory.allApps => contact.type == 'app',
      ContactDirectoryCategory.joinedGroups =>
        contact.type == 'group' && contact.joined,
      ContactDirectoryCategory.publicGroups =>
        contact.type == 'group' && contact.visibility == 'public',
    };
  }).toList();
  _sortContacts(values);
  return values;
}

void _sortContacts(List<Contact> values) {
  final sortKeys = <String, String>{
    for (final contact in values)
      contact.id: _contactSortKey(contact.displayName),
  };
  values.sort((left, right) {
    final byName =
        (sortKeys[left.id] ?? '').compareTo(sortKeys[right.id] ?? '');
    return byName != 0 ? byName : left.id.compareTo(right.id);
  });
}

String _contactSortKey(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  return PinyinHelper.getPinyinE(text,
          separator: '', format: PinyinFormat.WITHOUT_TONE, defPinyin: '#')
      .toLowerCase();
}

String? _latinInitial(String value) {
  const groups = {
    'A': 'ÀÁÂÃÄÅĀĂĄàáâãäåāăą',
    'C': 'ÇĆĈČçćĉč',
    'E': 'ÈÉÊËĒĔĖĘĚèéêëēĕėęě',
    'G': 'ĜĞĠĢĝğġģ',
    'I': 'ÌÍÎÏĨĪĬĮìíîïĩīĭį',
    'L': 'ĹĻĽŁĺļľł',
    'N': 'ÑŃŅŇñńņň',
    'O': 'ÒÓÔÕÖØŌŎŐòóôõöøōŏő',
    'R': 'ŔŖŘŕŗř',
    'S': 'ŚŜŞŠśŝşš',
    'U': 'ÙÚÛÜŨŪŬŮŰŲùúûüũūŭůűų',
    'Y': 'ÝŸŶýÿŷ',
    'Z': 'ŹŻŽźżž',
  };
  for (final entry in groups.entries) {
    if (entry.value.contains(value)) return entry.key;
  }
  return null;
}
