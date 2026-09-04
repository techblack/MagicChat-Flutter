import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../domain/message_content.dart';
import '../../domain/models.dart';

Future<void> showConversationTopicsDialog(
  BuildContext context, {
  required MagicChatRepository repository,
  required String conversationId,
  ValueChanged<String>? onOpenTopic,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ConversationTopicsDialog(
      repository: repository,
      conversationId: conversationId,
      onOpenTopic: onOpenTopic,
    ),
  );
}

class ConversationTopicsDialog extends StatefulWidget {
  const ConversationTopicsDialog({
    required this.repository,
    required this.conversationId,
    this.onOpenTopic,
    super.key,
  });

  final MagicChatRepository repository;
  final String conversationId;
  final ValueChanged<String>? onOpenTopic;

  @override
  State<ConversationTopicsDialog> createState() =>
      _ConversationTopicsDialogState();
}

class _ConversationTopicsDialogState extends State<ConversationTopicsDialog> {
  final _topics = <ChatConversation>[];
  late final Future<List<Contact>> _contactsFuture;
  String _status = 'all';
  String? _nextCursor;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _contactsFuture = widget.repository.contacts();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    if (_loading || (next && _nextCursor == null)) return;
    final cursor = next ? _nextCursor : null;
    setState(() {
      _loading = true;
      if (!next) _error = null;
    });
    try {
      final page = await widget.repository.topics(
        widget.conversationId,
        cursor: cursor,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        if (!next) _topics.clear();
        final existing = _topics.map((item) => item.id).toSet();
        _topics.addAll(page.topics.where((item) => existing.add(item.id)));
        final nextCursor = page.nextCursor?.trim();
        _nextCursor =
            nextCursor == null || nextCursor.isEmpty || nextCursor == cursor
                ? null
                : nextCursor;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(String value) async {
    if (value == _status) return;
    setState(() {
      _status = value;
      _topics.clear();
      _nextCursor = null;
      _error = null;
    });
    await _load();
  }

  Future<void> _openTopic(ChatConversation topic) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => TopicDetailDialog(
        repository: widget.repository,
        conversationId: topic.id,
      ),
    );
    if (selected == null || !mounted) return;
    Navigator.pop(context);
    widget.onOpenTopic?.call(selected);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('话题'),
        content: SizedBox(
          width: 560,
          height: 460,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('全部')),
                    ButtonSegment(value: 'active', label: Text('进行中')),
                    ButtonSegment(value: 'archived', label: Text('已关闭')),
                  ],
                  selected: {_status},
                  onSelectionChanged:
                      _loading ? null : (value) => _changeStatus(value.single),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildContent(context)),
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

  Widget _buildContent(BuildContext context) {
    if (_error != null && _topics.isEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (_loading && _topics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_topics.isEmpty) {
      return const Center(child: Text('暂无话题，可从消息菜单创建话题'));
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _topics.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final topic = _topics[index];
              final metadata = topic.topic;
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(metadata?.archived == true
                      ? Icons.archive_outlined
                      : Icons.forum_outlined),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(topic.displayTitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (metadata?.archived == true)
                      const Chip(
                        label: Text('已关闭'),
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      const Chip(
                        label: Text('进行中'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                subtitle: FutureBuilder<List<Contact>>(
                  future: _contactsFuture,
                  builder: (context, snapshot) => Text(
                    topic.preview.isEmpty
                        ? '暂无回复'
                        : formatMentionText(
                            topic.preview,
                            (snapshot.data ?? const <Contact>[])
                                .map((contact) => (
                                      id: contact.id,
                                      name: contact.displayName,
                                    ))),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                trailing: metadata?.participating == true
                    ? const Icon(Icons.person_outline, size: 18)
                    : null,
                onTap: _loading ? null : () => _openTopic(topic),
              );
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '加载下一页失败',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _loading ? null : () => _load(next: true),
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: const Text('加载更多'),
            ),
          ),
      ],
    );
  }
}

class TopicDetailDialog extends StatefulWidget {
  const TopicDetailDialog({
    required this.repository,
    required this.conversationId,
    super.key,
  });

  final MagicChatRepository repository;
  final String conversationId;

  @override
  State<TopicDetailDialog> createState() => _TopicDetailDialogState();
}

class _TopicDetailDialogState extends State<TopicDetailDialog> {
  late final Future<List<Contact>> _contactsFuture;
  TopicDetail? _detail;
  Object? _error;
  bool _loading = true;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _contactsFuture = widget.repository.contacts();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.topicDetail(widget.conversationId);
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _participate() async {
    await _mutate(
      () => widget.repository.participateTopic(widget.conversationId),
      participated: true,
    );
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭话题'),
        content: const Text('关闭后将不能继续发送话题消息，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(
      () => widget.repository.archiveTopic(widget.conversationId),
      participated: false,
    );
  }

  Future<void> _mutate(
    Future<ChatConversation> Function() action, {
    required bool participated,
  }) async {
    if (_mutating) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      final conversation = await action();
      if (!mounted || _detail == null) return;
      setState(() {
        _detail = TopicDetail(
          canArchive: participated ? _detail!.canArchive : false,
          canParticipate: participated ? false : _detail!.canParticipate,
          conversation: conversation,
          parentConversation: _detail!.parentConversation,
          sourceMessage: _detail!.sourceMessage,
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return AlertDialog(
      title: const Text('话题详情'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : detail == null && _error != null
                ? TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('加载失败，点击重试'),
                  )
                : detail == null
                    ? const Text('话题不存在')
                    : FutureBuilder<List<Contact>>(
                        future: _contactsFuture,
                        builder: (context, snapshot) => _buildDetail(
                            detail, snapshot.data ?? const <Contact>[])),
      ),
      actions: [
        if (detail != null && detail.canParticipate)
          FilledButton.icon(
            onPressed: _mutating ? null : _participate,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('参与话题'),
          ),
        if (detail != null && detail.canArchive)
          OutlinedButton.icon(
            onPressed: _mutating ? null : _archive,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('关闭话题'),
          ),
        if (detail != null)
          FilledButton(
            onPressed: _mutating
                ? null
                : () => Navigator.pop(context, detail.conversation.id),
            child: const Text('打开话题'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildDetail(TopicDetail detail, List<Contact> contacts) {
    final source = detail.sourceMessage;
    final body = source.revokedAt != null
        ? '消息已撤回'
        : MessageContent.parse(source.body).text;
    final names = {
      for (final contact in contacts) contact.id: contact.displayName,
    };
    final labels = contacts.map((contact) => (
          id: contact.id,
          name: contact.displayName,
        ));
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '操作失败：$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Text(
              '父会话：${detail.parentConversation.name == detail.parentConversation.id ? '会话' : detail.parentConversation.name}'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      names[source.sender.id] ??
                          (source.sender.name.isEmpty ||
                                  source.sender.name == source.sender.id
                              ? '成员'
                              : source.sender.name),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(formatMentionText(
                      body.isEmpty ? source.summary : body, labels)),
                  if (source.replyTo != null) ...[
                    const SizedBox(height: 8),
                    Text(
                        '回复 ${names[source.replyTo!.sender.id] ?? (source.replyTo!.sender.name.isEmpty || source.replyTo!.sender.name == source.replyTo!.sender.id ? '成员' : source.replyTo!.sender.name)}：${formatMessageReferenceText(source.replyTo!.summary, labels, messageId: source.replyTo!.id)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
