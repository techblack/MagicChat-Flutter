import 'package:flutter/material.dart';

import '../../domain/message_content.dart';
import '../../domain/models.dart';

/// 话题消息区顶部的来源消息上下文。
class TopicSourceBanner extends StatelessWidget {
  const TopicSourceBanner(
      {required this.detail, this.contactsFuture, super.key});

  final TopicDetail detail;
  final Future<List<Contact>>? contactsFuture;

  @override
  Widget build(BuildContext context) {
    final source = detail.sourceMessage;
    final body = source.revokedAt != null
        ? '消息已撤回'
        : MessageContent.parse(source.body).text;
    final senderName = source.sender.displayName;
    return FutureBuilder<List<Contact>>(
      future: contactsFuture,
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? const <Contact>[];
        final names = {
          for (final contact in contacts)
            contact.id.toLowerCase(): contact.displayName,
        };
        final labels = contacts.map((contact) => (
              id: contact.id,
              name: contact.displayName,
            ));
        final resolvedSenderName =
            names[source.sender.id.toLowerCase()] ?? senderName;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  child: Text(resolvedSenderName.isEmpty
                      ? '?'
                      : resolvedSenderName.substring(0, 1)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '来自 ${detail.parentConversation.displayName} 的来源消息',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(resolvedSenderName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Text(_formatTime(source.createdAt),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      Text(
                        formatMentionText(
                            body.isEmpty ? source.summary : body, labels),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (source.replyTo != null)
                        Text(
                          '回复 ${names[source.replyTo!.sender.id.toLowerCase()] ?? source.replyTo!.sender.displayName}：${formatMessageReferenceText(source.replyTo!.summary, labels, messageId: source.replyTo!.id)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (detail.conversation.topic?.archived == true)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text('已关闭'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(String value) {
    final time = DateTime.tryParse(value)?.toLocal();
    if (time == null) return '';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
