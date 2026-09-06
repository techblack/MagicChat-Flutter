import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinyin/pinyin.dart';

import '../../data/contact_cache_store.dart';
import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/message_content.dart';
import '../../domain/models.dart';
import '../shared/user_facing_error.dart';

enum GlobalSearchResultType { conversation, contact, project, message }

/// 综合搜索的一条结果。会话、通讯录和项目来自已加载的客户端数据，
/// 消息结果来自服务端全文搜索。
class GlobalSearchResult {
  const GlobalSearchResult._({
    required this.key,
    required this.type,
    this.matchDescription,
    this.conversation,
    this.contact,
    this.project,
    this.message,
  });

  GlobalSearchResult.conversation(ChatConversation value,
      {String? matchDescription})
      : this._(
            key: 'conversation:${value.id}',
            type: GlobalSearchResultType.conversation,
            matchDescription: matchDescription,
            conversation: value);

  GlobalSearchResult.contact(Contact value, {String? matchDescription})
      : this._(
            key: 'contact:${value.type}:${value.id}',
            type: GlobalSearchResultType.contact,
            matchDescription: matchDescription,
            contact: value);

  GlobalSearchResult.project(Project value, {String? matchDescription})
      : this._(
            key: 'project:${value.id}',
            type: GlobalSearchResultType.project,
            matchDescription: matchDescription,
            project: value);

  GlobalSearchResult.message(MessageSearchResult value)
      : this._(
            key: 'message:${value.conversationId}:${value.message.id}',
            type: GlobalSearchResultType.message,
            message: value);

  final String key;
  final GlobalSearchResultType type;
  final String? matchDescription;
  final ChatConversation? conversation;
  final Contact? contact;
  final Project? project;
  final MessageSearchResult? message;
}

/// 组合本地索引和服务端消息搜索结果，保持稳定的分组顺序。
List<GlobalSearchResult> buildGlobalSearchResults({
  required String keyword,
  required List<ChatConversation> conversations,
  required List<Contact> contacts,
  required List<Project> projects,
  required List<MessageSearchResult> messages,
}) {
  final query = _normalizeSearchValue(keyword);
  if (query.isEmpty) return const [];

  final conversationResults = <_RankedGlobalSearchResult>[];
  for (var index = 0; index < conversations.length; index++) {
    final conversation = conversations[index];
    final fields = <_SearchField>[
      _SearchField(conversation.displayTitle, 0, '匹配会话名称'),
      _SearchField(conversation.preview, 6, '匹配最近消息'),
      _SearchField(conversation.announcement, 7, '匹配群公告'),
    ];
    if (conversation.type != 'app') {
      for (final member in conversation.members) {
        final displayName = member.displayName;
        final namePriority = conversation.type == 'direct' ? 1 : 2;
        fields
          ..add(
              _SearchField(member.nickname, namePriority, '匹配成员：$displayName'))
          ..add(_SearchField(member.name, namePriority, '匹配成员：$displayName'))
          ..add(_SearchField(member.email, 3,
              _matchedMemberValue('邮箱', displayName, member.email)))
          ..add(_SearchField(member.phone, 4,
              _matchedMemberValue('手机号', displayName, member.phone)));
      }
    }
    final match = _bestMatch(fields, query);
    if (match == null) continue;
    conversationResults.add(_RankedGlobalSearchResult(
      result: GlobalSearchResult.conversation(conversation,
          matchDescription: match.description),
      quality: match.quality,
      fieldPriority: match.field.priority,
      recentActivityAt: _conversationActivityAt(conversation),
      originalIndex: index,
    ));
  }
  conversationResults.sort(_compareRankedResults);

  final contactResults = <_RankedGlobalSearchResult>[];
  for (var index = 0; index < contacts.length; index++) {
    final contact = contacts[index];
    final fields = contact.type == 'user'
        ? [
            _SearchField(contact.nickname, 0, '匹配昵称'),
            _SearchField(contact.name, 0, '匹配姓名'),
            _SearchField(contact.email, 1, '匹配邮箱：${contact.email}'),
            _SearchField(contact.phone, 2, '匹配手机号：${contact.phone}'),
          ]
        : contact.type == 'app'
            ? [
                _SearchField(contact.name, 0, '匹配应用名称'),
                _SearchField(contact.description, 1, '匹配应用介绍'),
              ]
            : [_SearchField(contact.name, 0, '匹配群组名称')];
    final match = _bestMatch(fields, query);
    if (match == null) continue;
    contactResults.add(_RankedGlobalSearchResult(
      result: GlobalSearchResult.contact(contact,
          matchDescription: match.description),
      quality: match.quality,
      fieldPriority: match.field.priority,
      originalIndex: index,
    ));
  }
  contactResults.sort(_compareRankedResults);

  final projectResults = <_RankedGlobalSearchResult>[];
  for (var index = 0; index < projects.length; index++) {
    final project = projects[index];
    final match = _bestMatch([
      _SearchField(project.name, 0, '匹配项目名称'),
      _SearchField(project.description, 1, '匹配项目介绍'),
    ], query);
    if (match == null) continue;
    projectResults.add(_RankedGlobalSearchResult(
      result: GlobalSearchResult.project(project,
          matchDescription: match.description),
      quality: match.quality,
      fieldPriority: match.field.priority,
      originalIndex: index,
    ));
  }
  projectResults.sort(_compareRankedResults);

  return [
    ...conversationResults.take(_localResultLimit).map((item) => item.result),
    ...contactResults.take(_localResultLimit).map((item) => item.result),
    ...projectResults.take(_localResultLimit).map((item) => item.result),
    ...messages.map(GlobalSearchResult.message),
  ];
}

const _localResultLimit = 20;

enum _SearchMatchQuality { exact, prefix, contains }

class _SearchField {
  _SearchField(String value, this.priority, this.description)
      : tokens = _searchTokens(value);

  final int priority;
  final String description;
  final List<String> tokens;
}

class _SearchMatch {
  const _SearchMatch(this.field, this.quality);

  final _SearchField field;
  final _SearchMatchQuality quality;
  String get description => field.description;
}

class _RankedGlobalSearchResult {
  const _RankedGlobalSearchResult({
    required this.result,
    required this.quality,
    required this.fieldPriority,
    required this.originalIndex,
    this.recentActivityAt = 0,
  });

  final GlobalSearchResult result;
  final _SearchMatchQuality quality;
  final int fieldPriority;
  final int originalIndex;
  final int recentActivityAt;
}

_SearchMatch? _bestMatch(Iterable<_SearchField> fields, String query) {
  _SearchMatch? best;
  for (final field in fields) {
    for (final token in field.tokens) {
      final quality = token == query
          ? _SearchMatchQuality.exact
          : token.startsWith(query)
              ? _SearchMatchQuality.prefix
              : token.contains(query)
                  ? _SearchMatchQuality.contains
                  : null;
      if (quality == null) continue;
      final candidate = _SearchMatch(field, quality);
      if (best == null ||
          quality.index < best.quality.index ||
          (quality == best.quality && field.priority < best.field.priority)) {
        best = candidate;
      }
    }
  }
  return best;
}

int _compareRankedResults(
    _RankedGlobalSearchResult left, _RankedGlobalSearchResult right) {
  final quality = left.quality.index.compareTo(right.quality.index);
  if (quality != 0) return quality;
  final field = left.fieldPriority.compareTo(right.fieldPriority);
  if (field != 0) return field;
  final activity = right.recentActivityAt.compareTo(left.recentActivityAt);
  return activity != 0
      ? activity
      : left.originalIndex.compareTo(right.originalIndex);
}

List<String> _searchTokens(String value) {
  final normalized = _normalizeSearchValue(value);
  if (normalized.isEmpty) return const [];
  final tokens = <String>{normalized};
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(value)) {
    tokens
      ..add(_normalizeSearchValue(PinyinHelper.getPinyinE(value,
          separator: '', format: PinyinFormat.WITHOUT_TONE)))
      ..add(_normalizeSearchValue(PinyinHelper.getShortPinyin(value)));
  }
  return tokens.where((token) => token.isNotEmpty).toList(growable: false);
}

String _normalizeSearchValue(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

String _matchedMemberValue(String label, String displayName, String value) {
  final normalized = value.trim();
  return displayName == normalized
      ? '匹配$label：$normalized'
      : '匹配$label：$displayName · $normalized';
}

int _conversationActivityAt(ChatConversation conversation) =>
    DateTime.tryParse(conversation.lastMessageAt.isNotEmpty
            ? conversation.lastMessageAt
            : conversation.createdAt)
        ?.millisecondsSinceEpoch ??
    0;

/// 综合搜索对话框。消息搜索最少需要两个字符；其余结果支持单字符关键词。
class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({
    required this.repository,
    required this.onOpenConversation,
    this.cacheScope,
    this.contactCacheStore,
    this.onOpenMessage,
    this.onOpenProject,
    this.onOpenContact,
    super.key,
  });

  final MagicChatRepository repository;
  final MessageCacheScope? cacheScope;
  final ContactCacheStore? contactCacheStore;
  final ValueChanged<String> onOpenConversation;
  final void Function(
          String conversationId, String messageId, int? messageSequence)?
      onOpenMessage;
  final ValueChanged<String>? onOpenProject;
  final ValueChanged<Contact>? onOpenContact;

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  final _controller = TextEditingController();
  String _keyword = '';
  Future<List<GlobalSearchResult>>? _results;
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  late final Future<List<Contact>> _cachedContacts;
  List<Contact> _displayContacts = const [];
  List<GlobalSearchResult> _visibleResults = const [];
  final _resultKeys = <String, GlobalKey>{};
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    _cachedContacts = (widget.contactCacheStore ?? ContactCacheStore())
        .read(widget.cacheScope);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<List<GlobalSearchResult>> _search(String keyword) async {
    final local = await Future.wait([
      widget.repository.conversations(),
      widget.repository.contacts(keyword: keyword),
      widget.repository.projects(),
      _cachedContacts,
    ]);
    final messages = keyword.trim().characters.length >= 2
        ? await widget.repository.searchMessages(keyword.trim())
        : const <MessageSearchResult>[];
    final contacts = <String, Contact>{
      for (final contact in local[3] as List<Contact>)
        '${contact.type}:${contact.id.toLowerCase()}': contact,
      for (final contact in local[1] as List<Contact>)
        '${contact.type}:${contact.id.toLowerCase()}': contact,
    }.values.toList(growable: false);
    _displayContacts = contacts;
    final results = buildGlobalSearchResults(
      keyword: keyword,
      conversations: local[0] as List<ChatConversation>,
      contacts: contacts,
      projects: local[2] as List<Project>,
      messages: messages,
    );
    if (mounted && keyword == _keyword) {
      _visibleResults = results;
      _activeIndex = -1;
    }
    return results;
  }

  void _onChanged(String value) {
    final keyword = value.trim();
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _keyword = keyword;
      _results = null;
      _visibleResults = const [];
      _activeIndex = -1;
      _resultKeys.clear();
    });
    if (keyword.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = _search(keyword);
      });
    });
  }

  void _open(GlobalSearchResult result) {
    Navigator.pop(context);
    switch (result.type) {
      case GlobalSearchResultType.conversation:
        widget.onOpenConversation(result.conversation!.id);
      case GlobalSearchResultType.message:
        final message = result.message!;
        final openMessage = widget.onOpenMessage;
        if (openMessage != null) {
          openMessage(message.conversationId, message.message.id,
              message.message.sequence);
        } else {
          widget.onOpenConversation(message.conversationId);
        }
      case GlobalSearchResultType.project:
        widget.onOpenProject?.call(result.project!.id);
      case GlobalSearchResultType.contact:
        widget.onOpenContact?.call(result.contact!);
    }
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _visibleResults.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    var next = _activeIndex;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = _activeIndex < _visibleResults.length - 1 ? _activeIndex + 1 : 0;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = _activeIndex <= 0 ? _visibleResults.length - 1 : _activeIndex - 1;
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = _visibleResults.length - 1;
    } else if (key == LogicalKeyboardKey.enter && _activeIndex >= 0) {
      _open(_visibleResults[_activeIndex]);
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    setState(() => _activeIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next < 0 || next >= _visibleResults.length) return;
      final target = _resultKeys[_visibleResults[next].key]?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.35);
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('综合搜索'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: _handleSearchKeyEvent,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: '搜索消息、联系人和项目',
                    suffixIcon: _keyword.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(height: 12),
              if (_keyword.isNotEmpty)
                Flexible(
                  child: FutureBuilder<List<GlobalSearchResult>>(
                    future: _results,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('搜索失败：${userFacingError(snapshot.error!)}'),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _onChanged(_keyword),
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                          ],
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final results = snapshot.data!;
                      if (results.isEmpty) return const Text('没有匹配的结果');
                      return _resultList(results);
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );

  Widget _resultList(List<GlobalSearchResult> results) {
    final grouped = <GlobalSearchResultType, List<GlobalSearchResult>>{};
    for (final result in results) {
      grouped.putIfAbsent(result.type, () => []).add(result);
    }
    const labels = {
      GlobalSearchResultType.conversation: '会话',
      GlobalSearchResultType.contact: '联系人',
      GlobalSearchResultType.project: '项目',
      GlobalSearchResultType.message: '聊天记录',
    };
    final children = <Widget>[];
    final indexes = {
      for (var index = 0; index < _visibleResults.length; index++)
        _visibleResults[index].key: index,
    };
    for (final type in GlobalSearchResultType.values) {
      final values = grouped[type];
      if (values == null || values.isEmpty) continue;
      children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(labels[type]!,
              style: Theme.of(context).textTheme.labelLarge)));
      children.addAll(values
          .map((result) => _resultTile(result, indexes[result.key] ?? -1)));
    }
    return Semantics(
      container: true,
      label: '搜索结果',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView(shrinkWrap: true, children: children),
      ),
    );
  }

  Widget _resultTile(GlobalSearchResult result, int index) {
    final key = _resultKeys.putIfAbsent(result.key, GlobalKey.new);
    final selected = index >= 0 && index == _activeIndex;
    Widget tile(Widget child) => KeyedSubtree(
          key: key,
          child: Semantics(
            selected: selected,
            button: true,
            label: selected ? '已选中搜索结果' : null,
            child: child,
          ),
        );
    switch (result.type) {
      case GlobalSearchResultType.conversation:
        final value = result.conversation!;
        return tile(ListTile(
          key: ValueKey(result.key),
          selected: selected,
          leading: const Icon(Icons.chat_bubble_outline),
          title: Text(value.displayTitle),
          subtitle: Text(result.matchDescription ??
              '会话 · ${_conversationType(value.type)}'),
          onTap: () => _open(result),
        ));
      case GlobalSearchResultType.contact:
        final value = result.contact!;
        return tile(ListTile(
          key: ValueKey(result.key),
          selected: selected,
          leading: const Icon(Icons.person_outline),
          title: Text(value.displayName),
          subtitle: Text(
              result.matchDescription ?? '联系人 · ${_contactType(value.type)}'),
          onTap: () => _open(result),
        ));
      case GlobalSearchResultType.project:
        final value = result.project!;
        return tile(ListTile(
          key: ValueKey(result.key),
          selected: selected,
          leading: const Icon(Icons.folder_outlined),
          title: Text(value.name),
          subtitle: Text(result.matchDescription ??
              '项目 · ${value.description.isEmpty ? '暂无说明' : value.description}'),
          onTap: () => _open(result),
        ));
      case GlobalSearchResultType.message:
        final value = result.message!;
        final text = formatMentionText(
            value.message.text,
            _displayContacts.map((contact) => (
                  id: contact.id,
                  name: contact.displayName,
                )));
        return tile(ListTile(
          key: ValueKey(result.key),
          selected: selected,
          leading: const Icon(Icons.message_outlined),
          title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(value.displayConversationName),
          onTap: () => _open(result),
        ));
    }
  }

  String _conversationType(String type) => switch (type) {
        'group' => '群聊',
        'app' => '应用',
        'topic' => '话题',
        _ => '私聊',
      };

  String _contactType(String type) => switch (type) {
        'group' => '群组',
        'app' => '应用',
        _ => '用户',
      };
}
