import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import 'project_avatar.dart';

class ProjectWorkspacePage extends StatelessWidget {
  const ProjectWorkspacePage({
    required this.project,
    required this.repository,
    required this.onCreateTask,
    required this.child,
    this.serverUrl,
    this.cacheScope,
    this.onEditProject,
    super.key,
  });

  final Project project;
  final MagicChatRepository repository;
  final VoidCallback onCreateTask;
  final Widget child;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final VoidCallback? onEditProject;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('project-workspace-page'),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Row(children: [
            ProjectAvatar(
              repository: repository,
              project: project,
              serverUrl: serverUrl,
              cacheScope: cacheScope,
              radius: 16,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(project.name)),
          ]),
          actions: [
            if (onEditProject != null)
              IconButton(
                onPressed: onEditProject,
                icon: const Icon(Icons.more_horiz),
                tooltip: '编辑项目信息',
              ),
            IconButton(
              key: const ValueKey('project-workspace-create-task'),
              onPressed: onCreateTask,
              icon: const Icon(Icons.add),
              tooltip: '新建任务',
            ),
          ],
        ),
        body: SafeArea(top: false, child: child),
      );
}
