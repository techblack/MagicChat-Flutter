import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';

typedef SendCardToConversation = Future<void> Function(String conversationId);

class SendCardDialog extends StatefulWidget {
  const SendCardDialog({
    required this.repository,
    required this.cardTitle,
    required this.cardDescription,
    required this.onSend,
    super.key,
  });

  final MagicChatRepository repository;
  final String cardTitle;
  final String cardDescription;
  final SendCardToConversation onSend;

  @override
  State<SendCardDialog> createState() => _SendCardDialogState();
}

class _SendCardDialogState extends State<SendCardDialog> {
  late Future<List<ChatConversation>> _conversations =
      widget.repository.conversations();
  String _keyword = '';
  String _selectedConversationId = '';
  bool _sending = false;

  Future<void> _send(List<ChatConversation> conversations) async {
    if (_selectedConversationId.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(_selectedConversationId);
      if (!mounted) return;
      final conversation = conversations
          .where((item) => item.id == _selectedConversationId)
          .firstOrNull;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
          content: Text(conversation == null
              ? '卡片已发送'
              : '卡片已发送到 ${conversation.displayTitle}')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送卡片失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contentHeight =
        (MediaQuery.sizeOf(context).height * .55).clamp(200.0, 420.0);
    return AlertDialog(
      title: const Text('发送卡片'),
      content: SizedBox(
        width: 420,
        height: contentHeight,
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.task_alt_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(widget.cardDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('send-card-search'),
            enabled: !_sending,
            onChanged: (value) => setState(() => _keyword = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索会话',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<ChatConversation>>(
              future: _conversations,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _conversations = widget.repository.conversations();
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('会话加载失败，点击重试'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final keyword = _keyword.trim().toLowerCase();
                final conversations = snapshot.data!
                    .where(
                        (item) => item.canSend && item.topic?.archived != true)
                    .where((item) =>
                        keyword.isEmpty ||
                        item.displayTitle.toLowerCase().contains(keyword))
                    .toList();
                if (conversations.isEmpty) {
                  return Center(
                      child: Text(keyword.isEmpty ? '暂无可发送的会话' : '没有匹配的会话'));
                }
                return RadioGroup<String>(
                  groupValue: _selectedConversationId,
                  onChanged: (value) =>
                      setState(() => _selectedConversationId = value ?? ''),
                  child: ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return RadioListTile<String>(
                        key: ValueKey(
                            'send-card-conversation-${conversation.id}'),
                        value: conversation.id,
                        enabled: !_sending,
                        title: Text(conversation.displayTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_conversationType(conversation.type)),
                        secondary: Icon(_conversationIcon(conversation.type)),
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('取消')),
        FutureBuilder<List<ChatConversation>>(
          future: _conversations,
          builder: (context, snapshot) => FilledButton.icon(
            onPressed: snapshot.hasData &&
                    _selectedConversationId.isNotEmpty &&
                    !_sending
                ? () => _send(snapshot.data!)
                : null,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_outlined),
            label: Text(_sending ? '发送中…' : '发送'),
          ),
        ),
      ],
    );
  }

  String _conversationType(String type) => switch (type) {
        'group' => '群聊',
        'app' => '应用会话',
        'topic' => '话题',
        _ => '私聊',
      };

  IconData _conversationIcon(String type) => switch (type) {
        'group' => Icons.groups_outlined,
        'app' => Icons.smart_toy_outlined,
        'topic' => Icons.forum_outlined,
        _ => Icons.person_outline,
      };
}
