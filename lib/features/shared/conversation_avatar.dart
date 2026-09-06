import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import 'cached_avatar.dart';

List<Contact> groupAvatarMembers(Iterable<Contact> members) {
  final indexed = members.indexed
      .where((entry) =>
          entry.$2.avatar.trim().isNotEmpty ||
          (entry.$2.nickname.trim().isNotEmpty &&
              entry.$2.nickname.trim().toLowerCase() !=
                  entry.$2.id.trim().toLowerCase()) ||
          (entry.$2.name.trim().isNotEmpty &&
              entry.$2.name.trim().toLowerCase() !=
                  entry.$2.id.trim().toLowerCase()))
      .toList();
  int roleOrder(String role) => switch (role) {
        'owner' => 0,
        'admin' => 1,
        _ => 2,
      };
  indexed.sort((left, right) {
    final byRole = roleOrder(left.$2.role).compareTo(roleOrder(right.$2.role));
    return byRole != 0 ? byRole : left.$1.compareTo(right.$1);
  });
  return indexed.take(4).map((entry) => entry.$2).toList(growable: false);
}

class ConversationAvatar extends StatelessWidget {
  const ConversationAvatar({
    required this.repository,
    required this.conversation,
    this.serverUrl,
    this.cacheScope,
    this.radius = 16,
    super.key,
  });

  final MagicChatRepository repository;
  final ChatConversation conversation;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final explicitAvatar = _assetUri(serverUrl, conversation.avatar);
    if (conversation.type != 'group' || explicitAvatar != null) {
      return CachedAvatar(
        repository: repository,
        cacheScope: cacheScope,
        avatarUri: explicitAvatar,
        name: conversation.displayTitle,
        radius: radius,
        borderRadius: conversation.type == 'group'
            ? BorderRadius.circular(size * .18)
            : null,
      );
    }

    final members = groupAvatarMembers(conversation.members);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: conversation.displayTitle,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .18),
          child: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: SizedBox.square(
              dimension: size,
              child: members.isEmpty
                  ? Icon(Icons.groups_outlined,
                      size: size * .54, color: colors.onSurfaceVariant)
                  : Padding(
                      padding: const EdgeInsets.all(2),
                      child: Stack(children: [
                        for (var index = 0; index < members.length; index++)
                          _memberTile(
                              context, members[index], index, members.length),
                      ]),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberTile(
      BuildContext context, Contact member, int index, int count) {
    final innerSize = radius * 2 - 4;
    final tileSize = innerSize / 2;
    final placement = _tilePlacement(index, count, tileSize);
    final colors = Theme.of(context).colorScheme;
    final tileColors = [
      (colors.primaryContainer, colors.onPrimaryContainer),
      (colors.secondaryContainer, colors.onSecondaryContainer),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
      (colors.surfaceContainerHigh, colors.onSurface),
    ];
    return Positioned(
      key: ValueKey('group-avatar-member-${member.id}'),
      left: placement.dx,
      top: placement.dy,
      width: tileSize,
      height: tileSize,
      child: Padding(
        padding: const EdgeInsets.all(.6),
        child: CachedAvatar(
          repository: repository,
          cacheScope: cacheScope,
          avatarUri: _assetUri(serverUrl, member.avatar),
          name: member.displayName,
          radius: tileSize / 2,
          borderRadius: BorderRadius.zero,
          backgroundColor: tileColors[index].$1,
          foregroundColor: tileColors[index].$2,
        ),
      ),
    );
  }
}

Offset _tilePlacement(int index, int count, double tileSize) {
  if (count <= 1) return Offset(tileSize / 2, tileSize / 2);
  if (count == 2) return Offset(index * tileSize, tileSize / 2);
  if (count == 3) {
    return index == 0
        ? Offset(tileSize / 2, 0)
        : Offset((index - 1) * tileSize, tileSize);
  }
  return Offset((index % 2) * tileSize, (index ~/ 2) * tileSize);
}

Uri? _assetUri(String? serverUrl, String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  final parsed = Uri.tryParse(normalized);
  if (parsed == null) return null;
  if (parsed.hasScheme) return parsed;
  final server = Uri.tryParse(serverUrl ?? '');
  return server?.resolve(normalized);
}
