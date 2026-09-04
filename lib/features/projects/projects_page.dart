import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../data/document_collaboration.dart';
import '../../domain/models.dart';
import 'document_editor_page.dart';
import 'project_task_calendar_view.dart';
import 'project_task_details_page.dart';

typedef DocumentCollaborationFactory = DocumentCollaborationSession? Function(
    ProjectDocument document);

class ProjectsPage extends StatefulWidget {
  const ProjectsPage(
      {required this.repository,
      this.initialProjectId,
      this.onInitialProjectOpened,
      this.documentCollaborationFactory,
      super.key});
  final MagicChatRepository repository;
  final String? initialProjectId;
  final VoidCallback? onInitialProjectOpened;
  final DocumentCollaborationFactory? documentCollaborationFactory;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late Future<List<Project>> _projects;
  final _searchController = TextEditingController();
  String _search = '';
  String? _openedInitialProjectId;

  MagicChatRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _projects = repository.projects();
  }

  void _reloadProjects() {
    setState(() {
      _projects = repository.projects();
    });
  }

  Future<void> _refreshProjects() async {
    final future = repository.projects();
    setState(() {
      _projects = future;
    });
    await future;
  }

  void _openInitialProject(List<Project> projects) {
    final id = widget.initialProjectId;
    if (id == null || id.isEmpty || id == _openedInitialProjectId) return;
    Project? project;
    for (final item in projects) {
      if (item.id == id) {
        project = item;
        break;
      }
    }
    if (project == null) return;
    final target = project;
    _openedInitialProjectId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showTasks(context, target).whenComplete(() {
          widget.onInitialProjectOpened?.call();
        }));
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProjectsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId == null) _openedInitialProjectId = null;
    if (oldWidget.initialProjectId != widget.initialProjectId) {
      unawaited(_projects.then(_openInitialProject));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        FutureBuilder<List<Project>>(
            future: _projects,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 40),
                  const SizedBox(height: 12),
                  Text('项目加载失败：${snapshot.error}'),
                  TextButton.icon(
                      onPressed: _reloadProjects,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试')),
                ]));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              _openInitialProject(snapshot.data!);
              final keyword = _search.trim().toLowerCase();
              final projects = keyword.isEmpty
                  ? snapshot.data!
                  : snapshot.data!
                      .where((project) =>
                          project.name.toLowerCase().contains(keyword) ||
                          project.description.toLowerCase().contains(keyword))
                      .toList();
              return RefreshIndicator(
                  onRefresh: _refreshProjects,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    itemCount: projects.isEmpty ? 2 : projects.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                            child: TextField(
                                controller: _searchController,
                                onChanged: (value) =>
                                    setState(() => _search = value),
                                decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.search),
                                    hintText: '搜索项目',
                                    suffixIcon: _search.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: '清除搜索',
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _search = '');
                                            },
                                            icon: const Icon(Icons.clear)),
                                    border: const OutlineInputBorder())));
                      }
                      if (projects.isEmpty) {
                        return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                                child: Text(
                                    keyword.isEmpty ? '暂无项目' : '未找到匹配的项目')));
                      }
                      final project = projects[index - 1];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        leading: CircleAvatar(
                            backgroundColor: project.isPersonal
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                            child: Icon(project.isPersonal
                                ? Icons.person_outline
                                : Icons.folder_outlined)),
                        title: Row(children: [
                          Flexible(child: Text(project.name)),
                          if (project.isPersonal) ...[
                            const SizedBox(width: 8),
                            const Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('个人')),
                          ]
                        ]),
                        subtitle: Text(project.description.isNotEmpty
                            ? project.description
                            : project.isPersonal
                                ? '仅自己可见的个人项目'
                                : '团队项目'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (project.taskCount case final count?)
                            Text('$count 个任务'),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ]),
                        onTap: () => _showTasks(context, project),
                        onLongPress: () => _projectActions(context, project),
                      );
                    },
                  ));
            }),
        Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
                onPressed: () => _createProject(context),
                tooltip: '新建项目',
                child: const Icon(Icons.create_new_folder))),
      ]);

  Future<void> _projectActions(BuildContext context, Project project) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑项目'),
                  onTap: () => Navigator.pop(context, 'edit')),
              if (!project.isPersonal)
                ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('授权群组'),
                    onTap: () => Navigator.pop(context, 'groups')),
              if (!project.isPersonal)
                ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('删除项目'),
                    onTap: () => Navigator.pop(context, 'delete')),
            ])));
    if (!context.mounted || action == null) return;
    if (action == 'groups') {
      await _projectGroupAccess(context, project);
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('删除项目？'),
                  content: Text('将删除“${project.name}”及其任务。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'))
                  ]));
      if (ok == true) {
        await repository.deleteProject(project.id);
        _reloadProjects();
      }
    } else {
      final controller = TextEditingController(text: project.name);
      final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('编辑项目'),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('保存'))
                  ]));
      controller.dispose();
      if (name != null && name.isNotEmpty && context.mounted) {
        await repository.updateProject(project.id, name: name);
        _reloadProjects();
      }
    }
  }

  Future<void> _createProject(BuildContext context) async {
    var groups = const <ChatConversation>[];
    try {
      groups = (await repository.conversations())
          .where((conversation) => conversation.type == 'group')
          .toList();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('群聊加载失败，将创建未关联群聊的项目：$error')));
      }
    }
    if (!context.mounted) return;
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final selectedGroupIds = <String>{};
    var groupKeyword = '';
    final result = await showDialog<
            ({String name, String description, List<String> groupIds})>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('新建项目'),
                content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameController,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: '项目名称')),
                      TextField(
                          controller: descriptionController,
                          decoration: const InputDecoration(labelText: '描述')),
                      if (groups.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: Text('关联群聊（可选）',
                                style: Theme.of(context).textTheme.titleSmall)),
                        TextField(
                            decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: '搜索群聊'),
                            onChanged: (value) =>
                                setDialogState(() => groupKeyword = value)),
                        const SizedBox(height: 4),
                        SizedBox(
                            height: 180,
                            child: Builder(builder: (context) {
                              final keyword = groupKeyword.trim().toLowerCase();
                              final visible = keyword.isEmpty
                                  ? groups
                                  : groups
                                      .where((group) => group.title
                                          .toLowerCase()
                                          .contains(keyword))
                                      .toList();
                              if (visible.isEmpty) {
                                return const Center(child: Text('没有匹配的群聊'));
                              }
                              return ListView(
                                  children: visible
                                      .map((group) => CheckboxListTile(
                                          dense: true,
                                          value: selectedGroupIds
                                              .contains(group.id),
                                          title: Text(group.title),
                                          subtitle:
                                              Text('${group.members.length} 人'),
                                          onChanged: (checked) {
                                            setDialogState(() {
                                              if (checked == true) {
                                                if (selectedGroupIds.length <
                                                    100) {
                                                  selectedGroupIds
                                                      .add(group.id);
                                                }
                                              } else {
                                                selectedGroupIds
                                                    .remove(group.id);
                                              }
                                            });
                                          }))
                                      .toList());
                            }))
                      ]
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, (
                            name: nameController.text.trim(),
                            description: descriptionController.text.trim(),
                            groupIds: selectedGroupIds.toList()
                          )),
                      child: const Text('创建')),
                ],
              );
            }));
    unawaited(Future<void>.delayed(kThemeAnimationDuration, () {
      nameController.dispose();
      descriptionController.dispose();
    }));
    if (result == null || result.name.isEmpty || !context.mounted) return;
    try {
      await repository.createProject(result.name,
          description: result.description, groupIds: result.groupIds);
      _reloadProjects();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('项目已创建')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：$error')));
      }
    }
  }

  Future<List<ProjectTask>> _loadProjectTasks(String projectId,
      {String keyword = '',
      String label = '',
      String status = '',
      int priority = 0}) async {
    final tasks = <ProjectTask>[];
    String? cursor;
    do {
      final page = await repository.projectTaskPage(projectId,
          cursor: cursor,
          limit: 100,
          keyword: keyword,
          label: label,
          statuses: status.isEmpty ? const [] : [status],
          priorities: priority == 0 ? const [] : [priority]);
      tasks.addAll(page.tasks);
      final nextCursor = page.nextCursor;
      if (nextCursor == null || nextCursor.isEmpty || nextCursor == cursor) {
        break;
      }
      cursor = nextCursor;
    } while (true);
    return tasks;
  }

  Future<void> _showTasks(BuildContext context, Project project) async {
    var keyword = '';
    var label = '';
    var status = '';
    var priority = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setFilterState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: FutureBuilder<List<ProjectTask>>(
              future: _loadProjectTasks(project.id,
                  keyword: keyword,
                  label: label,
                  status: status,
                  priority: priority),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    const Text('任务加载失败'),
                    TextButton.icon(
                        onPressed: () => setFilterState(() {}),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'))
                  ]));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return DefaultTabController(
                  length: 7,
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(children: [
                        Expanded(
                            child: Text(project.name,
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            onPressed: () => _createTask(context, project),
                            icon: const Icon(Icons.add),
                            tooltip: '新建任务'),
                      ]),
                    ),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final search = TextField(
                              decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: '搜索任务',
                                  isDense: true),
                              onChanged: (value) =>
                                  setFilterState(() => keyword = value.trim()));
                          final labelFilter = TextField(
                              decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.label_outline),
                                  hintText: '按标签筛选',
                                  isDense: true),
                              onChanged: (value) =>
                                  setFilterState(() => label = value.trim()));
                          final statusFilter = SizedBox(
                              width: 120,
                              child: DropdownButtonFormField<String>(
                                  initialValue: status,
                                  isExpanded: true,
                                  isDense: true,
                                  decoration: const InputDecoration(
                                      labelText: '状态', isDense: true),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '', child: Text('全部状态')),
                                    DropdownMenuItem(
                                        value: 'todo', child: Text('待处理')),
                                    DropdownMenuItem(
                                        value: 'in_progress',
                                        child: Text('进行中')),
                                    DropdownMenuItem(
                                        value: 'done', child: Text('已完成')),
                                    DropdownMenuItem(
                                        value: 'canceled', child: Text('已取消')),
                                  ],
                                  onChanged: (value) => setFilterState(
                                      () => status = value ?? '')));
                          final priorityFilter = SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<int>(
                                  initialValue: priority,
                                  isExpanded: true,
                                  isDense: true,
                                  decoration: const InputDecoration(
                                      labelText: '优先级', isDense: true),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 0, child: Text('全部')),
                                    DropdownMenuItem(
                                        value: 1, child: Text('高')),
                                    DropdownMenuItem(
                                        value: 2, child: Text('中')),
                                    DropdownMenuItem(
                                        value: 3, child: Text('低')),
                                  ],
                                  onChanged: (value) => setFilterState(
                                      () => priority = value ?? 0)));
                          if (constraints.maxWidth >= 720) {
                            return Row(children: [
                              Expanded(child: search),
                              const SizedBox(width: 8),
                              Expanded(child: labelFilter),
                              const SizedBox(width: 8),
                              statusFilter,
                              const SizedBox(width: 8),
                              priorityFilter,
                            ]);
                          }
                          return Column(children: [
                            search,
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: labelFilter),
                              const SizedBox(width: 8),
                              statusFilter,
                              const SizedBox(width: 8),
                              priorityFilter,
                            ])
                          ]);
                        })),
                    const TabBar(isScrollable: true, tabs: [
                      Tab(text: '列表'),
                      Tab(text: '看板'),
                      Tab(text: '日历'),
                      Tab(text: '甘特'),
                      Tab(text: '文档'),
                      Tab(text: '目标'),
                      Tab(text: '成员')
                    ]),
                    Expanded(
                        child: TabBarView(children: [
                      ListView(
                          padding: const EdgeInsets.all(16),
                          children: snapshot.data!
                              .map((task) => _taskTile(context, project, task))
                              .toList()),
                      _taskBoard(context, project, snapshot.data!),
                      ProjectTaskCalendarView(
                          tasks: snapshot.data!,
                          onOpenTask: (task) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ProjectTaskDetailsPage(
                                      repository: repository,
                                      project: project,
                                      task: task)))),
                      _taskGantt(context, project, snapshot.data!),
                      _documentsView(context, project),
                      _goalsView(context),
                      _membersView(context, project),
                    ])),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskTile(BuildContext context, Project project, ProjectTask task) =>
      ListTile(
        leading: IconButton(
            tooltip: '推进任务状态',
            onPressed: () => _cycleTaskStatus(context, project, task),
            icon: Icon(task.status == 'done'
                ? Icons.check_circle
                : Icons.radio_button_unchecked)),
        title: Text(task.title),
        subtitle: Text(_taskMetadata(task),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              if (!context.mounted) return;
              if (action == 'edit') {
                await _editTask(context, project, task);
                return;
              }
              if (action != 'delete') return;
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: const Text('删除任务？'),
                        content: Text('将删除“${task.title}”。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除'))
                        ],
                      ));
              if (ok == true) {
                await repository.deleteTask(project.id, task.id);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑任务')),
                  PopupMenuItem(value: 'delete', child: Text('删除任务'))
                ]),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ProjectTaskDetailsPage(
                    repository: repository, project: project, task: task))),
        onLongPress: () => _addComment(context, project, task),
      );

  Future<void> _editTask(
      BuildContext context, Project project, ProjectTask task) async {
    List<ProjectMember> members;
    try {
      members = await repository.projectMembers(project.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('项目成员加载失败：$error')));
      }
      return;
    }
    if (!context.mounted) return;
    final titleController = TextEditingController(text: task.title);
    final descriptionController = TextEditingController(text: task.description);
    final startController = TextEditingController(text: task.startDate ?? '');
    final dueController = TextEditingController(text: task.dueDate ?? '');
    final labelsController =
        TextEditingController(text: task.labels.join(', '));
    final reminderController =
        TextEditingController(text: task.reminder?['at']?.toString() ?? '');
    var status = task.status;
    var priority = task.priority;
    var assigneeUserId = task.assigneeUserId ?? '';
    var reminderMode = task.reminder?['mode'] as String? ?? 'once';
    var reminderFrequency = task.reminder?['frequency'] as String? ?? 'daily';
    final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: const Text('编辑任务'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '标题')),
                  TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: '描述')),
                  DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: '状态'),
                      items: const [
                        DropdownMenuItem(value: 'todo', child: Text('待处理')),
                        DropdownMenuItem(
                            value: 'in_progress', child: Text('进行中')),
                        DropdownMenuItem(value: 'done', child: Text('已完成')),
                        DropdownMenuItem(value: 'canceled', child: Text('已取消'))
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => status = value);
                        }
                      }),
                  DropdownButtonFormField<int>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: '优先级'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('低')),
                        DropdownMenuItem(value: 2, child: Text('中')),
                        DropdownMenuItem(value: 3, child: Text('高'))
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => priority = value);
                        }
                      }),
                  TextField(
                      controller: startController,
                      decoration:
                          const InputDecoration(labelText: '开始日期（YYYY-MM-DD）')),
                  TextField(
                      controller: dueController,
                      decoration:
                          const InputDecoration(labelText: '截止日期（YYYY-MM-DD）')),
                  TextField(
                      controller: labelsController,
                      decoration: const InputDecoration(labelText: '标签（逗号分隔）')),
                  DropdownButtonFormField<String>(
                      initialValue: assigneeUserId,
                      decoration: const InputDecoration(labelText: '负责人'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('未分配')),
                        ...members.map((member) => DropdownMenuItem(
                            value: member.id,
                            child: Text(member.email.isEmpty
                                ? member.displayName
                                : '${member.displayName} · ${member.email}')))
                      ],
                      onChanged: (value) =>
                          setDialogState(() => assigneeUserId = value ?? '')),
                  TextField(
                      controller: reminderController,
                      decoration: const InputDecoration(
                          labelText: '一次性提醒时间（ISO-8601，可选）')),
                  DropdownButtonFormField<String>(
                      initialValue: reminderMode,
                      decoration: const InputDecoration(labelText: '提醒模式'),
                      items: const [
                        DropdownMenuItem(value: 'once', child: Text('一次性')),
                        DropdownMenuItem(value: 'recurring', child: Text('周期性'))
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => reminderMode = value);
                        }
                      }),
                  if (reminderMode == 'recurring')
                    DropdownButtonFormField<String>(
                        initialValue: reminderFrequency,
                        decoration: const InputDecoration(labelText: '重复频率'),
                        items: const [
                          DropdownMenuItem(value: 'daily', child: Text('每天')),
                          DropdownMenuItem(value: 'weekly', child: Text('每周')),
                          DropdownMenuItem(value: 'monthly', child: Text('每月'))
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => reminderFrequency = value);
                          }
                        }),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('保存'))
                ],
              ),
            ));
    if (result == true && context.mounted) {
      await repository.updateTask(
          project.id,
          task.id,
          ProjectTaskUpdate(
              title: titleController.text.trim(),
              description: descriptionController.text.trim(),
              status: status,
              priority: priority,
              startDate: startController.text.trim().isEmpty
                  ? null
                  : startController.text.trim(),
              dueDate: dueController.text.trim().isEmpty
                  ? null
                  : dueController.text.trim(),
              labels: labelsController.text
                  .split(',')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(),
              assigneeUserId: assigneeUserId.isEmpty ? null : assigneeUserId,
              reminder: reminderController.text.trim().isEmpty
                  ? null
                  : {
                      'mode': reminderMode,
                      'timezone': 'Asia/Shanghai',
                      if (reminderMode == 'once')
                        'at': reminderController.text.trim(),
                      if (reminderMode == 'recurring')
                        'frequency': reminderFrequency
                    }));
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
    titleController.dispose();
    descriptionController.dispose();
    startController.dispose();
    dueController.dispose();
    labelsController.dispose();
    reminderController.dispose();
  }

  Widget _goalsView(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.flag_outlined, size: 40),
            SizedBox(height: 12),
            Text('目标'),
            SizedBox(height: 4),
            Text('待完善', style: TextStyle(color: Colors.grey))
          ])));

  Widget _membersView(BuildContext context, Project project) =>
      FutureBuilder<List<ProjectMember>>(
          future: repository.projectMembers(project.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('成员加载失败：${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Center(child: Text('暂无项目成员'));
            }
            return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final member = snapshot.data![index];
                  final source = member.sourceGroupIds.isEmpty
                      ? ''
                      : ' · 来源群组 ${member.sourceGroupIds.length} 个';
                  return ListTile(
                      leading: CircleAvatar(
                          child: Text(member.displayName.isEmpty
                              ? '?'
                              : member.displayName.characters.first)),
                      title: Text(member.displayName),
                      subtitle: Text(
                          '${member.email.isEmpty ? '未提供邮箱' : member.email}$source'),
                      trailing: Text(member.role == 'owner' ? '所有者' : '成员'));
                });
          });

  Future<void> _projectGroupAccess(
      BuildContext context, Project project) async {
    try {
      final result = await Future.wait([
        repository.projectGroups(project.id),
        repository.conversations(),
      ]);
      if (!context.mounted) return;
      var linked = (result[0] as List<ProjectGroup>).toList();
      final groups = (result[1] as List<ChatConversation>)
          .where((item) => item.type == 'group')
          .toList();
      await showDialog<void>(
          context: context,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (dialogContext, setDialogState) {
                final linkedIds = linked.map((item) => item.id).toSet();
                final available = groups
                    .where((item) => !linkedIds.contains(item.id))
                    .toList();
                return AlertDialog(
                    title: const Text('授权群组'),
                    content: SizedBox(
                        width: 420,
                        child: ListView(shrinkWrap: true, children: [
                          if (linked.isEmpty)
                            const ListTile(title: Text('暂无授权群组')),
                          ...linked.map((group) => ListTile(
                              leading: const Icon(Icons.group_outlined),
                              title: Text(group.name),
                              subtitle: Text('${group.memberCount} 人'),
                              trailing: IconButton(
                                  tooltip: '取消授权',
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () async {
                                    await repository.unbindProjectGroup(
                                        project.id, group.id);
                                    if (dialogContext.mounted) {
                                      setDialogState(() => linked = linked
                                          .where((item) => item.id != group.id)
                                          .toList());
                                    }
                                  }))),
                          const Divider(),
                          if (available.isEmpty)
                            const ListTile(title: Text('没有可授权的群组')),
                          ...available.map((group) => ListTile(
                              leading: const Icon(Icons.add_circle_outline),
                              title: Text(group.title),
                              onTap: () async {
                                await repository.bindProjectGroup(
                                    project.id, group.id);
                                if (dialogContext.mounted) {
                                  setDialogState(() => linked = [
                                        ProjectGroup(
                                            id: group.id,
                                            name: group.title,
                                            avatar: group.avatar,
                                            memberCount: group.members.length),
                                        ...linked
                                      ]);
                                }
                              }))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('关闭'))
                    ]);
              }));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('授权群组加载失败：$error')));
      }
    }
  }

  Widget _documentsView(BuildContext context, Project project) =>
      FutureBuilder<List<ProjectDocument>>(
          future: repository.documents(project.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('文档加载失败：${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final documents = [
              ...snapshot.data!
            ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
            return Stack(children: [
              ListView(
                  padding: const EdgeInsets.all(16),
                  children: _documentNodes(context, project, documents, null)),
              Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                      onPressed: () => _createDocument(context, project),
                      tooltip: '新建文档',
                      child: const Icon(Icons.note_add_outlined))),
            ]);
          });

  List<Widget> _documentNodes(BuildContext context, Project project,
          List<ProjectDocument> documents, String? parentId) =>
      documents.where((item) => item.parentId == parentId).map((document) {
        if (document.kind == 'folder') {
          return InkWell(
              onLongPress: () => _documentActions(context, project, document),
              child: ExpansionTile(
                  key: PageStorageKey(document.id),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(document.title),
                  subtitle: const Text('目录'),
                  children: _documentNodes(
                      context, project, documents, document.id)));
        }
        return ListTile(
            leading: Icon(document.documentType == 'markdown'
                ? Icons.code_outlined
                : Icons.description_outlined),
            title: Text(document.title),
            subtitle: Text(
                document.documentType == 'markdown' ? 'Markdown 文档' : '富文本文档'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DocumentEditorPage(
                        repository: repository,
                        document: document,
                        collaboration: widget.documentCollaborationFactory
                            ?.call(document)))),
            onLongPress: () => _documentActions(context, project, document));
      }).toList();

  Future<void> _createDocument(BuildContext context, Project project,
      {String? parentId}) async {
    final controller = TextEditingController();
    var kind = 'document';
    var documentType = 'document';
    final result = await showDialog<
            ({String title, String kind, String? documentType})>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                    title: const Text('新建文档'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: '名称')),
                      DropdownButtonFormField<String>(
                          initialValue: kind,
                          decoration: const InputDecoration(labelText: '类型'),
                          items: const [
                            DropdownMenuItem(
                                value: 'document', child: Text('文档')),
                            DropdownMenuItem(value: 'folder', child: Text('目录'))
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => kind = value);
                          }),
                      if (kind == 'document')
                        DropdownButtonFormField<String>(
                            initialValue: documentType,
                            decoration:
                                const InputDecoration(labelText: '文档格式'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'document', child: Text('富文本')),
                              DropdownMenuItem(
                                  value: 'markdown', child: Text('Markdown'))
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => documentType = value);
                              }
                            })
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, (
                                title: controller.text.trim(),
                                kind: kind,
                                documentType:
                                    kind == 'document' ? documentType : null
                              )),
                          child: const Text('创建'))
                    ])));
    controller.dispose();
    if (result == null || result.title.isEmpty || !context.mounted) return;
    await repository.createDocument(project.id, result.title,
        kind: result.kind,
        documentType: result.documentType,
        parentId: parentId);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文档已创建，请重新打开项目查看')));
    }
  }

  Future<void> _documentActions(
      BuildContext context, Project project, ProjectDocument document) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('重命名'),
                  onTap: () => Navigator.pop(context, 'rename')),
              if (document.kind == 'folder')
                ListTile(
                    leading: const Icon(Icons.note_add_outlined),
                    title: const Text('在目录内新建'),
                    onTap: () => Navigator.pop(context, 'create')),
              ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除'),
                  onTap: () => Navigator.pop(context, 'delete')),
              ListTile(
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: const Text('移动到目录'),
                  onTap: () => Navigator.pop(context, 'move')),
            ])));
    if (!context.mounted || action == null) return;
    if (action == 'create') {
      await _createDocument(context, project, parentId: document.id);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('删除文档？'),
                  content: Text('将删除“${document.title}”。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'))
                  ]));
      if (ok == true) await repository.deleteDocument(document.id);
    } else if (action == 'move') {
      final documents = await repository.documents(document.projectId);
      if (!context.mounted) return;
      final folders = documents
          .where((item) => item.kind == 'folder' && item.id != document.id)
          .toList();
      final parentId = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
                title: const Text('选择目标目录'),
                children: [
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, ''),
                      child: const Text('项目根目录')),
                  ...folders.map((folder) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, folder.id),
                      child: Text(folder.title))),
                ],
              ));
      if (parentId != null && context.mounted) {
        await repository.moveDocument(document.id,
            parentId: parentId.isEmpty ? null : parentId, index: 0);
      }
    } else {
      final controller = TextEditingController(text: document.title);
      final title = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('重命名文档'),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('保存'))
                  ]));
      controller.dispose();
      if (title != null && title.isNotEmpty && context.mounted) {
        if (document.kind == 'folder') {
          await repository.updateDocument(document.id, title: title);
        } else {
          await repository.updateCollaborativeDocumentTitle(document.id, title);
        }
      }
    }
  }

  Widget _taskBoard(
      BuildContext context, Project project, List<ProjectTask> tasks) {
    const statuses = ['todo', 'in_progress', 'done', 'canceled'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: statuses.map((status) {
              final items =
                  tasks.where((task) => task.status == status).toList();
              return SizedBox(
                  width: 230,
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_statusLabel(status),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const Divider(),
                                ...items.map((task) =>
                                    _taskTile(context, project, task)),
                              ]))));
            }).toList()),
      ),
    );
  }

  Widget _taskGantt(
      BuildContext context, Project project, List<ProjectTask> tasks) {
    final dated = tasks
        .where((task) => task.startDate != null || task.dueDate != null)
        .toList();
    if (dated.isEmpty) {
      return const Center(child: Text('暂无排期任务'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('时间线（横向滚动查看）'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 720,
            child: Column(
              children: dated.map((task) {
                final start =
                    DateTime.tryParse(task.startDate ?? task.dueDate!);
                final due = DateTime.tryParse(task.dueDate ?? task.startDate!);
                final days = start != null && due != null
                    ? due.difference(start).inDays.abs() + 1
                    : 1;
                return ListTile(
                  title: Text(task.title),
                  subtitle: Text(
                      '${task.startDate ?? '未设置'} → ${task.dueDate ?? '未设置'}'),
                  trailing: SizedBox(
                      width: (days * 18).clamp(18, 360).toDouble(),
                      child: LinearProgressIndicator(
                          value: task.status == 'done'
                              ? 1
                              : task.status == 'in_progress'
                                  ? .5
                                  : .1)),
                  onTap: () => _cycleTaskStatus(context, project, task),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cycleTaskStatus(
      BuildContext context, Project project, ProjectTask task) async {
    final next = task.status == 'todo'
        ? 'in_progress'
        : task.status == 'in_progress'
            ? 'done'
            : 'todo';
    await repository.updateTaskStatus(project.id, task.id, next);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _createTask(BuildContext context, Project project) async {
    List<ProjectMember> members;
    try {
      members = await repository.projectMembers(project.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('项目成员加载失败：$error')));
      }
      return;
    }
    if (!context.mounted) return;
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final startController = TextEditingController();
    final dueController = TextEditingController();
    final labelsController = TextEditingController();
    final reminderController = TextEditingController();
    var priority = 2;
    var assigneeUserId = '';
    var reminderMode = 'once';
    var reminderFrequency = 'daily';
    final result = await showDialog<ProjectTaskUpdate>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: const Text('新建任务'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: titleController,
                      autofocus: true,
                      maxLength: 240,
                      decoration: const InputDecoration(labelText: '任务标题')),
                  TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: '描述', hintText: '支持 Markdown')),
                  DropdownButtonFormField<int>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: '优先级'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('低')),
                        DropdownMenuItem(value: 2, child: Text('中')),
                        DropdownMenuItem(value: 3, child: Text('高'))
                      ],
                      onChanged: (value) =>
                          setDialogState(() => priority = value ?? priority)),
                  DropdownButtonFormField<String>(
                      initialValue: assigneeUserId,
                      decoration: const InputDecoration(labelText: '负责人'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('未分配')),
                        ...members.map((member) => DropdownMenuItem(
                            value: member.id,
                            child: Text(member.email.isEmpty
                                ? member.displayName
                                : '${member.displayName} · ${member.email}')))
                      ],
                      onChanged: (value) =>
                          setDialogState(() => assigneeUserId = value ?? '')),
                  TextField(
                      controller: startController,
                      decoration:
                          const InputDecoration(labelText: '开始日期（YYYY-MM-DD）')),
                  TextField(
                      controller: dueController,
                      decoration:
                          const InputDecoration(labelText: '截止日期（YYYY-MM-DD）')),
                  TextField(
                      controller: labelsController,
                      decoration: const InputDecoration(labelText: '标签（逗号分隔）')),
                  TextField(
                      controller: reminderController,
                      decoration: const InputDecoration(
                          labelText: '一次性提醒时间（ISO-8601，可选）')),
                  DropdownButtonFormField<String>(
                      initialValue: reminderMode,
                      decoration: const InputDecoration(labelText: '提醒模式'),
                      items: const [
                        DropdownMenuItem(value: 'once', child: Text('一次性')),
                        DropdownMenuItem(value: 'recurring', child: Text('周期性'))
                      ],
                      onChanged: (value) => setDialogState(
                          () => reminderMode = value ?? reminderMode)),
                  if (reminderMode == 'recurring')
                    DropdownButtonFormField<String>(
                        initialValue: reminderFrequency,
                        decoration: const InputDecoration(labelText: '重复频率'),
                        items: const [
                          DropdownMenuItem(value: 'daily', child: Text('每天')),
                          DropdownMenuItem(value: 'weekly', child: Text('每周')),
                          DropdownMenuItem(value: 'monthly', child: Text('每月'))
                        ],
                        onChanged: (value) => setDialogState(() =>
                            reminderFrequency = value ?? reminderFrequency))
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;
                        Navigator.pop(
                            dialogContext,
                            ProjectTaskUpdate(
                                title: title,
                                description: descriptionController.text.trim(),
                                status: 'todo',
                                priority: priority,
                                startDate: startController.text.trim().isEmpty
                                    ? null
                                    : startController.text.trim(),
                                dueDate: dueController.text.trim().isEmpty
                                    ? null
                                    : dueController.text.trim(),
                                labels: labelsController.text
                                    .split(',')
                                    .map((value) => value.trim())
                                    .where((value) => value.isNotEmpty)
                                    .toList(),
                                assigneeUserId: assigneeUserId.isEmpty
                                    ? null
                                    : assigneeUserId,
                                reminder: reminderController.text.trim().isEmpty
                                    ? null
                                    : {
                                        'mode': reminderMode,
                                        'timezone': 'Asia/Shanghai',
                                        if (reminderMode == 'once')
                                          'at': reminderController.text.trim(),
                                        if (reminderMode == 'recurring')
                                          'frequency': reminderFrequency
                                      }));
                      },
                      child: const Text('创建'))
                ],
              ),
            ));
    titleController.dispose();
    descriptionController.dispose();
    startController.dispose();
    dueController.dispose();
    labelsController.dispose();
    reminderController.dispose();
    if (result == null || !context.mounted) return;
    try {
      await repository.createTask(project.id, result.title,
          description: result.description,
          status: result.status,
          priority: result.priority,
          startDate: result.startDate,
          dueDate: result.dueDate,
          labels: result.labels,
          assigneeUserId: result.assigneeUserId,
          reminder: result.reminder);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建任务失败：$error')));
      }
    }
  }

  Future<void> _addComment(
      BuildContext context, Project project, ProjectTask task) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('评论：${task.title}'),
        content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: '评论内容')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('发送')),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty || !context.mounted) return;
    await repository.addTaskComment(project.id, task.id, content);
  }

  String _taskMetadata(ProjectTask task) {
    final values = <String>[
      _statusLabel(task.status),
      '${_priorityLabel(task.priority)}优先级',
    ];
    if (task.assignee case final assignee?) {
      values.add('负责人：${assignee.displayName}');
    }
    if (task.startDate != null || task.dueDate != null) {
      values.add('排期：${task.startDate ?? '未设置'} → ${task.dueDate ?? '未设置'}');
    }
    if (task.labels.isNotEmpty) {
      values.add('标签：${task.labels.join('、')}');
    }
    return values.join(' · ');
  }

  String _statusLabel(String status) => switch (status) {
        'todo' => '待处理',
        'in_progress' => '进行中',
        'done' => '已完成',
        'canceled' => '已取消',
        _ => status,
      };

  String _priorityLabel(int priority) => switch (priority) {
        1 => '低',
        3 => '高',
        _ => '中',
      };
}
