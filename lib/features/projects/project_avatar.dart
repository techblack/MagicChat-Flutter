import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/cached_avatar.dart';

class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({
    required this.repository,
    required this.project,
    this.serverUrl,
    this.cacheScope,
    this.radius = 20,
    super.key,
  });

  final MagicChatRepository repository;
  final Project project;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatarUri = _resolveProjectAvatarUri(serverUrl, project.avatar);
    if (!project.isPersonal && avatarUri == null) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.amber.shade700,
          borderRadius: BorderRadius.circular(radius * .3),
        ),
        child: Icon(
          Icons.business_center_outlined,
          size: radius,
          color: Colors.white,
        ),
      );
    }
    return CachedAvatar(
      repository: repository,
      cacheScope: cacheScope,
      avatarUri: avatarUri,
      name: project.name,
      radius: radius,
      borderRadius: BorderRadius.circular(radius * .3),
    );
  }
}

Uri? _resolveProjectAvatarUri(String? serverUrl, String value) {
  final avatar = Uri.tryParse(value.trim());
  if (avatar == null || value.trim().isEmpty) return null;
  if (avatar.hasScheme) return avatar;
  return Uri.tryParse(serverUrl ?? '')?.resolveUri(avatar);
}
