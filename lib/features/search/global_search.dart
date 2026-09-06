import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.conversation,
    this.contact,
    this.project,
    this.message,
  });

  GlobalSearchResult.conversation(ChatConversation value)
      : this._(
            key: 'conversation:${value.id}',
            type: GlobalSearchResultType.conversation,
            conversation: value);

  GlobalSearchResult.contact(Contact value)
      : this._(
            key: 'contact:${value.type}:${value.id}',
            type: GlobalSearchResultType.contact,
            contact: value);

  GlobalSearchResult.project(Project value)
      : this._(
            key: 'project:${value.id}',
            type: GlobalSearchResultType.project,
            project: value);

  GlobalSearchResult.message(MessageSearchResult value)
      : this._(
            key: 'message:${value.conversationId}:${value.message.id}',
            type: GlobalSearchResultType.message,
            message: value);

  final String key;
  final GlobalSearchResultType type;
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
  final normalized = keyword.trim().toLowerCase();
  if (normalized.isEmpty) return const [];

  bool matches(Iterable<String> values) =>
      values.any((value) => value.trim().toLowerCase().contains(normalized));

  final result = <GlobalSearchResult>[];
  for (final conversation in conversations) {
    final memberValues = conversation.members.expand((member) => [
          member.id,
          member.name,
          member.nickname,
          member.email,
          member.phone,
        ]);
    if (matches([
      conversation.id,
      conversation.title,
      conversation.preview,
      conversation.announcement,
      ...memberValues,
    ])) {
      result.add(GlobalSearchResult.conversation(conversation));
    }
  }
  for (final contact in contacts) {
    if (matches([
      contact.id,
      contact.name,
      contact.nickname,
      contact.email,
      contact.phone,
    ])) {
      result.add(GlobalSearchResult.contact(contact));
    }
  }
  for (final project in projects) {
    if (matches([project.id, project.name, project.description])) {
      result.add(GlobalSearchResult.project(project));
    }
  }
  result.addAll(messages.map(GlobalSearchResult.message));
  return result;
}

/// 综合搜索对话框。消息搜索最少需要两个字符；其余结果支持单字符关键词。
class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({
    required this.repository,
    required this.onOpenConversation,
    this.onOpenMessage,
    this.onOpenProject,
    this.onOpenContact,
    super.key,
  });

  final MagicChatRepository repository;
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
  List<Contact> _displayContacts = const [];
  List<GlobalSearchResult> _visibleResults = const [];
  final _resultKeys = <String, GlobalKey>{};
  int _activeIndex = -1;

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
    ]);
    final messages = keyword.trim().characters.length >= 2
        ? await widget.repository.searchMessages(keyword.trim())
        : const <MessageSearchResult>[];
    _displayContacts = local[1] as List<Contact>;
    final results = buildGlobalSearchResults(
      keyword: keyword,
      conversations: local[0] as List<ChatConversation>,
      contacts: local[1] as List<Contact>,
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
          subtitle: Text('会话 · ${_conversationType(value.type)}'),
          onTap: () => _open(result),
        ));
      case GlobalSearchResultType.contact:
        final value = result.contact!;
        return tile(ListTile(
          key: ValueKey(result.key),
          selected: selected,
          leading: const Icon(Icons.person_outline),
          title: Text(value.displayName),
          subtitle: Text('联系人 · ${_contactType(value.type)}'),
          onTap: () => _open(result),
        ));
      case GlobalSearchResultType.project:
        final value = result.project!;
        return tile(ListTile(
          key: ValueKey(result.key),
          selected: selected,
          leading: const Icon(Icons.folder_outlined),
          title: Text(value.name),
          subtitle: Text(
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
