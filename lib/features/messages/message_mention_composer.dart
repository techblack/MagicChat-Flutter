import 'package:pinyin/pinyin.dart';

import '../../domain/models.dart';

const maxComposerMentionCandidates = 8;

class ComposerMentionTrigger {
  const ComposerMentionTrigger(
      {required this.start, required this.end, required this.query});

  final int start;
  final int end;
  final String query;
}

class ComposerMentionCandidate {
  const ComposerMentionCandidate({
    required this.id,
    required this.label,
    required this.targetType,
    required this.description,
    required this.searchText,
  });

  final String id;
  final String label;
  final String targetType;
  final String description;
  final String searchText;

  String get token =>
      targetType == 'all' ? '{(@user/all)}' : '{(@$targetType/$id)}';
}

ComposerMentionTrigger? composerMentionTrigger(
    String value, int selectionStart, int selectionEnd) {
  if (selectionStart != selectionEnd ||
      selectionStart < 0 ||
      selectionStart > value.length) {
    return null;
  }
  final beforeCursor = value.substring(0, selectionStart);
  final start = beforeCursor.lastIndexOf('@');
  if (start < 0) {
    return null;
  }
  final query = value.substring(start + 1, selectionStart);
  if (RegExp(r'[\s@]').hasMatch(query)) {
    return null;
  }
  return ComposerMentionTrigger(
      start: start, end: selectionStart, query: query);
}

List<ComposerMentionCandidate> composerMentionCandidates(
    Iterable<Contact> members, String query) {
  final values = <ComposerMentionCandidate>[
    const ComposerMentionCandidate(
      id: 'all',
      label: '所有人',
      targetType: 'all',
      description: '所有成员',
      searchText: '所有人 全体 all everyone',
    ),
  ];
  final seen = <String>{};
  for (final member in members) {
    if (member.id.trim().isEmpty ||
        (member.type != 'user' && member.type != 'app') ||
        !seen.add('${member.type}:${member.id.toLowerCase()}')) {
      continue;
    }
    final label = member.displayName.trim();
    if (label.isEmpty) {
      continue;
    }
    final fields = [
      label,
      member.name,
      member.nickname,
      member.email,
      member.phone,
      member.type,
    ];
    values.add(ComposerMentionCandidate(
      id: member.id,
      label: label,
      targetType: member.type,
      description: member.type == 'app'
          ? '应用'
          : member.email.trim().isNotEmpty
              ? member.email.trim()
              : member.phone.trim().isNotEmpty
                  ? member.phone.trim()
                  : '成员',
      searchText: _mentionSearchText(fields),
    ));
  }
  final normalized = _normalizeMentionQuery(query);
  return values
      .where((candidate) =>
          normalized.isEmpty || candidate.searchText.contains(normalized))
      .take(maxComposerMentionCandidates)
      .toList(growable: false);
}

({String text, int cursor}) insertComposerMention(String value,
    ComposerMentionTrigger trigger, ComposerMentionCandidate candidate) {
  final inserted = '${candidate.token} ';
  return (
    text: value.replaceRange(trigger.start, trigger.end, inserted),
    cursor: trigger.start + inserted.length,
  );
}

String _mentionSearchText(Iterable<String> values) {
  final text = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');
  return '${text.toLowerCase()} ${PinyinHelper.getPinyinE(text, separator: '', format: PinyinFormat.WITHOUT_TONE, defPinyin: '#').toLowerCase()}';
}

String _normalizeMentionQuery(String value) {
  final text = value.trim().toLowerCase();
  if (text.isEmpty) return '';
  return PinyinHelper.getPinyinE(text,
          separator: '', format: PinyinFormat.WITHOUT_TONE, defPinyin: '#')
      .toLowerCase();
}
