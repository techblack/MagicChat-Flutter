import 'package:flutter/material.dart';

import '../../domain/message_content.dart';
import '../../domain/models.dart';

/// 父会话来源消息下方的话题回复摘要，可点击打开话题会话。
class TopicReplyPreview extends StatelessWidget {
  const TopicReplyPreview(
      {required this.topic, this.contactsFuture, this.onOpen, super.key});

  final MessageTopic topic;
  final Future<List<Contact>>? contactsFuture;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Contact>>(
      future: contactsFuture,
      builder: (context, snapshot) {
        final contacts = {
          for (final contact in snapshot.data ?? const <Contact>[])
            contact.id.toLowerCase(): contact
        };
        return InkWell(
          onTap: onOpen == null ? null : () => onOpen!(topic.conversationId),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 8),
                for (final reply in topic.recentReplies.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        _ReplyAvatar(name: _senderName(reply.sender, contacts)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_senderName(reply.sender, contacts)}：${formatMessageReferenceText(reply.summary, contacts.values.map((contact) => (
                                  id: contact.id,
                                  name: contact.displayName
                                )), messageId: reply.id)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Icon(Icons.forum_outlined,
                        size: 17, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 5),
                    Text(topic.archived ? '话题已关闭' : '查看话题',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                    if (topic.recentReplies.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('${topic.recentReplies.length} 条回复',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _senderName(TopicSourceSender sender, Map<String, Contact> contacts) {
    final contact = contacts[sender.id.toLowerCase()];
    return contact?.displayName ?? sender.displayName;
  }
}

class _ReplyAvatar extends StatelessWidget {
  const _ReplyAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 10,
      child: Text(name.isEmpty ? '?' : name.substring(0, 1),
          style: const TextStyle(fontSize: 10)),
    );
  }
}
