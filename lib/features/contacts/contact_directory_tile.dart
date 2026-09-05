import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/cached_avatar.dart';

class ContactDirectoryTile extends StatelessWidget {
  const ContactDirectoryTile({
    required this.repository,
    required this.contact,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.serverUrl,
    this.cacheScope,
    super.key,
  });

  final MagicChatRepository repository;
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 64,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selected: selected,
        selectedTileColor: colors.primaryContainer,
        leading: CachedAvatar(
          repository: repository,
          cacheScope: cacheScope,
          avatarUri: resolveContactAvatarUri(serverUrl, contact.avatar),
          name: contact.displayName,
          radius: 22,
          backgroundColor: contact.type == 'app'
              ? colors.secondaryContainer
              : colors.primaryContainer,
        ),
        title: Text(contact.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: contact.type == 'group'
                    ? colors.onSurfaceVariant
                    : contact.online
                        ? Colors.green.shade700
                        : colors.onSurfaceVariant)),
        trailing: contact.type == 'group'
            ? Icon(contact.joined
                ? Icons.check_circle_outline
                : Icons.public_outlined)
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color:
                        contact.online ? Colors.green : colors.outlineVariant,
                    shape: BoxShape.circle)),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  String get _subtitle => contact.type == 'group'
      ? '${contact.memberCount} 人 · ${contact.joined ? '已加入' : contact.visibility == 'public' ? '公开群组' : '群组'}'
      : contact.type == 'app' && contact.description.trim().isNotEmpty
          ? contact.description.trim()
          : contact.online
              ? '在线'
              : '离线';
}

Uri? resolveContactAvatarUri(String? serverUrl, String value) {
  if (value.trim().isEmpty) return null;
  final parsed = Uri.tryParse(value);
  if (parsed == null) return null;
  if (parsed.hasScheme) return parsed;
  final server = Uri.tryParse(serverUrl ?? '');
  return server?.resolve(value);
}
