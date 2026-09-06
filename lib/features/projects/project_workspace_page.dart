import 'package:flutter/material.dart';

import '../../domain/models.dart';

class ProjectWorkspacePage extends StatelessWidget {
  const ProjectWorkspacePage({
    required this.project,
    required this.onCreateTask,
    required this.child,
    super.key,
  });

  final Project project;
  final VoidCallback onCreateTask;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('project-workspace-page'),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(project.name),
          actions: [
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
