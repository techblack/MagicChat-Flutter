import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/message_content.dart';
import '../../domain/models.dart';

enum ConversationMessageTypeFilter {
  all,
  text,
  image,
  file,
  voice,
  choice,
  linkOrCard,
  chart,
  forwardBundle,
  systemEvent,
}

bool matchesConversationMessageType(
    ChatMessage message, ConversationMessageTypeFilter filter) {
  return switch (filter) {
    ConversationMessageTypeFilter.all => true,
    ConversationMessageTypeFilter.text =>
      message.contentType == 'text' || message.contentType == 'markdown',
    ConversationMessageTypeFilter.image => message.contentType == 'image',
    ConversationMessageTypeFilter.file => message.contentType == 'file',
    ConversationMessageTypeFilter.voice => message.contentType == 'voice',
    ConversationMessageTypeFilter.choice => message.contentType == 'choice',
    ConversationMessageTypeFilter.linkOrCard =>
      message.contentType == 'link' || message.contentType == 'card',
    ConversationMessageTypeFilter.chart => message.contentType == 'chart',
    ConversationMessageTypeFilter.forwardBundle =>
      message.contentType == 'forward_bundle',
    ConversationMessageTypeFilter.systemEvent =>
      message.contentType == 'system_event',
  };
}

class AdvancedMessageSearchDialog extends StatefulWidget {
  const AdvancedMessageSearchDialog({
    required this.repository,
    required this.conversationId,
    required this.conversationName,
    required this.onOpenMessage,
    this.cacheScope,
    this.conversationType = 'direct',
    this.messageCacheStore,
    super.key,
  });

  final MagicChatRepository repository;
  final String conversationId;
  final String conversationName;
  final MessageCacheScope? cacheScope;
  final String conversationType;
  final MessageCacheStore? messageCacheStore;
  final void Function(
          String conversationId, String messageId, int? messageSequence)
      onOpenMessage;

  @override
  State<AdvancedMessageSearchDialog> createState() =>
      _AdvancedMessageSearchDialogState();
}

class _AdvancedMessageSearchDialogState
    extends State<AdvancedMessageSearchDialog> {
  final _keywordController = TextEditingController();
  late final MessageCacheStore _messageCacheStore =
      widget.messageCacheStore ?? MessageCacheStore();
  late final bool _ownsMessageCacheStore = widget.messageCacheStore == null;
  late final Future<List<Contact>> _sendersFuture = _loadSenders();
  Future<List<MessageSearchResult>>? _results;
  DateTimeRange? _dateRange;
  String _senderId = '';
  ConversationMessageTypeFilter _type = ConversationMessageTypeFilter.all;

  @override
  void dispose() {
    _keywordController.dispose();
    if (_ownsMessageCacheStore) unawaited(_messageCacheStore.close());
    super.dispose();
  }

  Future<List<Contact>> _loadSenders() async {
    final conversations = await widget.repository.conversations();
    ChatConversation? conversation;
    for (final item in conversations) {
      if (item.id == widget.conversationId) {
        conversation = item;
        break;
      }
    }
    final members = conversation?.members ?? const <Contact>[];
    if (members.isNotEmpty) return members;
    // 兼容旧服务端未在会话响应中返回成员资料的情况；新协议路径只
    // 展示当前会话成员，避免搜索弹窗再次加载整个组织通讯录。
    return widget.repository.contacts();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _dateRange,
      helpText: '选择消息时间范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );
    if (selected != null && mounted) setState(() => _dateRange = selected);
  }

  DateTime? _searchFrom(DateTime now) {
    final range = _dateRange;
    if (range == null) return null;
    final cutoff = DateTime(now.year - 1, now.month, now.day, now.hour,
        now.minute, now.second, now.millisecond, now.microsecond);
    return range.start.isBefore(cutoff) ? cutoff : range.start;
  }

  DateTime? _searchTo(DateTime now) {
    final range = _dateRange;
    if (range == null) return null;
    final endExclusive =
        DateTime(range.end.year, range.end.month, range.end.day + 1);
    final end = endExclusive.subtract(const Duration(microseconds: 1));
    return end.isAfter(now) ? now : end;
  }

  bool get _hasSearchCriteria =>
      _keywordController.text.trim().isNotEmpty ||
      _dateRange != null ||
      _senderId.isNotEmpty ||
      _type != ConversationMessageTypeFilter.all;

  void _search() {
    if (!_hasSearchCriteria) return;
    final now = DateTime.now();
    setState(() {
      _results = _searchMessages(
          keyword: _keywordController.text.trim(),
          from: _searchFrom(now),
          to: _searchTo(now));
    });
  }

  Future<List<MessageSearchResult>> _searchMessages(
      {required String keyword, DateTime? from, DateTime? to}) async {
    final localFuture = _searchLocal(keyword: keyword, from: from, to: to);
    Future<List<MessageSearchResult>> remoteFuture = Future.value(const []);
    if (keyword.characters.length >= 2) {
      remoteFuture = widget.repository.searchMessages(
        keyword,
        conversationId: widget.conversationId,
        senderId: _senderId,
        from: from,
        to: to,
      );
    }
    final local = await localFuture;
    List<MessageSearchResult> remote;
    try {
      remote = await remoteFuture;
    } catch (_) {
      if (local.isEmpty) rethrow;
      remote = const [];
    }
    final merged = <String, MessageSearchResult>{
      for (final result in local) result.message.id: result,
      for (final result in remote) result.message.id: result,
    }
        .values
        .where(
            (result) => matchesConversationMessageType(result.message, _type))
        .toList(growable: false)
      ..sort((left, right) {
        final leftAt = DateTime.tryParse(left.message.createdAt);
        final rightAt = DateTime.tryParse(right.message.createdAt);
        if (leftAt != null || rightAt != null) {
          if (leftAt == null) return 1;
          if (rightAt == null) return -1;
          final compared = rightAt.compareTo(leftAt);
          if (compared != 0) return compared;
        }
        return (right.message.sequence ?? 0)
            .compareTo(left.message.sequence ?? 0);
      });
    return merged;
  }

  Future<List<MessageSearchResult>> _searchLocal(
      {required String keyword, DateTime? from, DateTime? to}) async {
    final scope = widget.cacheScope;
    if (scope == null) return const [];
    final records = await _messageCacheStore.search(
      scope,
      widget.conversationId,
      keyword: keyword,
      senderId: _senderId,
      from: from,
      to: to,
      contentTypes: _contentTypes(_type),
      conversationType: widget.conversationType,
    );
    return records
        .map((record) {
          final message = ChatMessage(
            id: '${record['id'] ?? ''}',
            clientMessageId: record['client_message_id'] is String
                ? record['client_message_id'] as String
                : null,
            conversationId: widget.conversationId,
            sequence: (record['sequence'] as num?)?.toInt(),
            createdAt: record['created_at'] is String
                ? record['created_at'] as String
                : '',
            author: '${record['author'] ?? '成员'}',
            authorId: record['author_id'] is String
                ? record['author_id'] as String
                : null,
            contentType: '${record['content_type'] ?? 'text'}',
            rawBody: record['raw_body'] is Map
                ? Map<String, dynamic>.from(record['raw_body'] as Map)
                : const {},
            text: '${record['text'] ?? ''}',
            mine: record['mine'] == true,
          );
          return MessageSearchResult(
              conversationId: widget.conversationId,
              conversationName: widget.conversationName,
              message: message);
        })
        .where((result) => result.message.id.isNotEmpty)
        .toList(growable: false);
  }

  Iterable<String> _contentTypes(ConversationMessageTypeFilter filter) =>
      switch (filter) {
        ConversationMessageTypeFilter.all => const [],
        ConversationMessageTypeFilter.text => const ['text', 'markdown'],
        ConversationMessageTypeFilter.image => const ['image'],
        ConversationMessageTypeFilter.file => const ['file'],
        ConversationMessageTypeFilter.voice => const ['voice'],
        ConversationMessageTypeFilter.choice => const ['choice'],
        ConversationMessageTypeFilter.linkOrCard => const ['link', 'card'],
        ConversationMessageTypeFilter.chart => const ['chart'],
        ConversationMessageTypeFilter.forwardBundle => const ['forward_bundle'],
        ConversationMessageTypeFilter.systemEvent => const ['system_event'],
      };

  void _clearFilters() {
    setState(() {
      _dateRange = null;
      _senderId = '';
      _type = ConversationMessageTypeFilter.all;
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.conversationName} · 高级检索'),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(children: [
          TextField(
            key: const ValueKey('advanced-message-search-keyword'),
            controller: _keywordController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: '消息关键词',
              hintText: '可留空并按筛选条件检索缓存',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() => _results = null),
            onSubmitted: (_) => _hasSearchCriteria ? _search() : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('advanced-message-search-date'),
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_dateRangeLabel(context)),
              ),
            ),
            if (_dateRange != null)
              IconButton(
                tooltip: '清除时间范围',
                onPressed: () => setState(() {
                  _dateRange = null;
                  _results = null;
                }),
                icon: const Icon(Icons.close),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _senderPicker()),
            const SizedBox(width: 8),
            Expanded(child: _typePicker()),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            TextButton(onPressed: _clearFilters, child: const Text('清除筛选')),
            const Spacer(),
            FilledButton.icon(
              key: const ValueKey('advanced-message-search-submit'),
              onPressed: _hasSearchCriteria ? _search : null,
              icon: const Icon(Icons.manage_search),
              label: const Text('检索'),
            ),
          ]),
          const Divider(),
          Text('优先检索本地缓存；输入至少 2 个字符时同时查询远程最近一年记录',
              style: Theme.of(context).textTheme.bodySmall),
          Expanded(child: _resultPane()),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _senderPicker() => FutureBuilder<List<Contact>>(
        future: _sendersFuture,
        builder: (context, snapshot) {
          final senders = snapshot.data ?? const <Contact>[];
          return InputDecorator(
            decoration: const InputDecoration(labelText: '发送人', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('advanced-message-search-sender'),
                value: _senderId,
                isExpanded: true,
                isDense: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部发送人')),
                  ...senders.map((sender) => DropdownMenuItem(
                        value: sender.id,
                        child: Text(sender.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: snapshot.hasError
                    ? null
                    : (value) => setState(() {
                          _senderId = value ?? '';
                          _results = null;
                        }),
              ),
            ),
          );
        },
      );

  Widget _typePicker() => InputDecorator(
        decoration: const InputDecoration(labelText: '消息类型', isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<ConversationMessageTypeFilter>(
            key: const ValueKey('advanced-message-search-type'),
            value: _type,
            isExpanded: true,
            isDense: true,
            items: ConversationMessageTypeFilter.values
                .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(type),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(growable: false),
            onChanged: (value) => setState(() {
              _type = value ?? ConversationMessageTypeFilter.all;
              _results = null;
            }),
          ),
        ),
      );

  Widget _resultPane() {
    final future = _results;
    if (future == null) {
      return const Center(child: Text('设置筛选条件后检索当前会话'));
    }
    return FutureBuilder<List<MessageSearchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('检索失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data!;
        if (results.isEmpty) return const Center(child: Text('没有匹配的消息'));
        return FutureBuilder<List<Contact>>(
          future: _sendersFuture,
          builder: (context, senderSnapshot) {
            final contacts = senderSnapshot.data ?? const <Contact>[];
            final contactsById = {
              for (final contact in contacts) contact.id: contact,
            };
            final labels = contacts.map((contact) => (
                  id: contact.id,
                  name: contact.displayName,
                ));
            return ListView.separated(
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = results[index];
                final message = result.message;
                final author = contactsById[message.authorId]?.displayName ??
                    (message.author.trim().isEmpty ||
                            message.author == message.authorId
                        ? '成员'
                        : message.author);
                return ListTile(
                  key: ValueKey('advanced-message-search-result-${message.id}'),
                  leading: const Icon(Icons.message_outlined),
                  title: Text(formatMentionText(message.text, labels),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '$author · ${_messageTypeLabel(message.contentType)} · ${_messageTime(context, message.createdAt)}'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenMessage(
                        result.conversationId, message.id, message.sequence);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  String _dateRangeLabel(BuildContext context) {
    final range = _dateRange;
    if (range == null) return '全部时间';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatShortDate(range.start)} - ${localizations.formatShortDate(range.end)}';
  }

  String _messageTime(BuildContext context, String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '时间未知';
    final date = MaterialLocalizations.of(context).formatShortDate(parsed);
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$date $hour:$minute';
  }

  String _typeLabel(ConversationMessageTypeFilter type) => switch (type) {
        ConversationMessageTypeFilter.all => '全部类型',
        ConversationMessageTypeFilter.text => '文本与 Markdown',
        ConversationMessageTypeFilter.image => '图片',
        ConversationMessageTypeFilter.file => '文件',
        ConversationMessageTypeFilter.voice => '语音',
        ConversationMessageTypeFilter.choice => '选择',
        ConversationMessageTypeFilter.linkOrCard => '链接与卡片',
        ConversationMessageTypeFilter.chart => '图表',
        ConversationMessageTypeFilter.forwardBundle => '合并转发',
        ConversationMessageTypeFilter.systemEvent => '系统消息',
      };

  String _messageTypeLabel(String type) => switch (type) {
        'text' => '文本',
        'markdown' => 'Markdown',
        'image' => '图片',
        'file' => '文件',
        'voice' => '语音',
        'choice' => '选择',
        'link' => '链接',
        'card' => '卡片',
        'chart' => '图表',
        'forward_bundle' => '合并转发',
        'system_event' => '系统消息',
        _ => '其他',
      };
}
