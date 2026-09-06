import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pinyin/pinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/avatar_processor.dart';
import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../data/document_collaboration.dart';
import '../../data/realtime.dart';
import '../../domain/models.dart';
import 'document_editor_page.dart';
import 'project_avatar.dart';
import 'project_progress.dart';
import 'project_task_calendar_view.dart';
import 'project_task_details_page.dart';
import 'project_task_editor_dialog.dart';
import 'project_workspace_page.dart';
import '../shared/user_facing_error.dart';

typedef DocumentCollaborationFactory = DocumentCollaborationSession? Function(
    ProjectDocument document);
typedef ProjectAvatarPicker = Future<Uint8List?> Function();

const _projectTaskViewCount = 7;

String _projectTaskViewPreferenceKey(String projectId) =>
    'magicchat.project.task-view.$projectId';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage(
      {required this.repository,
      this.realtimeSession,
      this.initialProjectId,
      this.onInitialProjectOpened,
      this.initialTaskProjectId,
      this.initialTaskId,
      this.onInitialTaskOpened,
      this.initialDocumentId,
      this.onInitialDocumentOpened,
      this.documentCollaborationFactory,
      this.serverUrl,
      this.cacheScope,
      this.projectAvatarPicker,
      super.key});
  final MagicChatRepository repository;
  final RealtimeSession? realtimeSession;
  final String? initialProjectId;
  final VoidCallback? onInitialProjectOpened;
  final String? initialTaskProjectId;
  final String? initialTaskId;
  final VoidCallback? onInitialTaskOpened;
  final String? initialDocumentId;
  final VoidCallback? onInitialDocumentOpened;
  final DocumentCollaborationFactory? documentCollaborationFactory;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final ProjectAvatarPicker? projectAvatarPicker;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final _projects = <Project>[];
  final _searchController = TextEditingController();
  Project? _personalProject;
  String _search = '';
  String? _nextProjectsCursor;
  String? _failedProjectsCursor;
  Object? _projectsError;
  final _seenProjectsCursors = <String>{};
  bool _loadingProjects = false;
  bool _loadingMoreProjects = false;
  int _projectsRequestVersion = 0;
  String? _openedInitialProjectId;
  String? _openedInitialTaskKey;
  String? _openedInitialDocumentId;
  Timer? _fallbackPollTimer;
  Timer? _searchDebounce;
  bool _fallbackPollInFlight = false;

  MagicChatRepository get repository => widget.repository;
  List<Project> get _allProjects => [
        if (_personalProject != null) _personalProject!,
        ..._projects,
      ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects());
    if (widget.realtimeSession != null) {
      _fallbackPollTimer = Timer.periodic(
          const Duration(minutes: 5), (_) => unawaited(_pollFallback()));
    }
  }

  void _reloadProjects() => unawaited(_loadProjects());

  Future<void> _refreshProjects() => _loadProjects();

  Future<void> _loadProjects({bool next = false}) async {
    if (next) {
      if (_loadingProjects ||
          _loadingMoreProjects ||
          _nextProjectsCursor == null) {
        return;
      }
    } else {
      _projectsRequestVersion++;
    }
    final requestVersion = _projectsRequestVersion;
    final cursor = next ? _nextProjectsCursor : null;
    final keyword = _search.trim();
    final knownMatches = !next && keyword.isNotEmpty
        ? _allProjects
            .where((project) =>
                _projectSearchText(project).contains(keyword.toLowerCase()))
            .toList(growable: false)
        : const <Project>[];
    setState(() {
      if (next) {
        _loadingMoreProjects = true;
      } else {
        _loadingProjects = true;
      }
      _projectsError = null;
      _failedProjectsCursor = null;
    });
    try {
      final page = await repository.projectPage(
        cursor: cursor,
        limit: 50,
        keyword: keyword,
      );
      if (!mounted || requestVersion != _projectsRequestVersion) return;
      setState(() {
        if (!next) {
          _projects.clear();
          _seenProjectsCursors.clear();
          _personalProject = page.personalProject?.id.isEmpty == true
              ? null
              : page.personalProject;
        }
        if (cursor != null) _seenProjectsCursors.add(cursor);
        final existing = {
          if (_personalProject != null) _personalProject!.id,
          ..._projects.map((project) => project.id),
        };
        _projects.addAll(page.projects.where(
            (project) => project.id.isNotEmpty && existing.add(project.id)));
        _projects.addAll(knownMatches.where(
            (project) => project.id.isNotEmpty && existing.add(project.id)));
        final nextCursor = page.nextCursor?.trim();
        _nextProjectsCursor = nextCursor == null ||
                nextCursor.isEmpty ||
                nextCursor == cursor ||
                _seenProjectsCursors.contains(nextCursor)
            ? null
            : nextCursor;
        _loadingProjects = false;
        _loadingMoreProjects = false;
      });
      _openInitialProject(_allProjects);
      _openInitialTask(_allProjects);
      _openInitialDocument(_allProjects);
    } catch (error) {
      if (!mounted || requestVersion != _projectsRequestVersion) return;
      setState(() {
        _projectsError = error;
        _failedProjectsCursor = cursor;
        _loadingProjects = false;
        _loadingMoreProjects = false;
      });
      if (_allProjects.isEmpty) _completeFailedInitialTargets();
    }
  }

  void _searchProjects(String value) {
    setState(() {
      _search = value;
      _nextProjectsCursor = null;
      _seenProjectsCursors.clear();
      _failedProjectsCursor = null;
      _projectsError = null;
      _loadingMoreProjects = false;
    });
    _searchDebounce?.cancel();
    _projectsRequestVersion++;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_loadProjects());
    });
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
    final target = project ?? Project(id: id, name: '');
    _openedInitialProjectId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showTasks(target).whenComplete(() {
          widget.onInitialProjectOpened?.call();
        }));
      }
    });
  }

  void _openInitialDocument(List<Project> projects) {
    final id = widget.initialDocumentId;
    if (id == null || id.isEmpty || id == _openedInitialDocumentId) return;
    _openedInitialDocumentId = id;
    unawaited(_showInitialDocument(id, projects));
  }

  void _openInitialTask(List<Project> projects) {
    final projectId = widget.initialTaskProjectId;
    final taskId = widget.initialTaskId;
    if (projectId == null || taskId == null) return;
    final key = '$projectId:$taskId';
    if (projectId.isEmpty || taskId.isEmpty || key == _openedInitialTaskKey) {
      return;
    }
    _openedInitialTaskKey = key;
    unawaited(_showInitialTask(projectId, taskId, projects));
  }

  Future<void> _showInitialTask(
      String projectId, String taskId, List<Project> projects) async {
    try {
      final project =
          projects.where((item) => item.id == projectId).firstOrNull ??
              await repository.project(projectId);
      final task = await repository.task(projectId, taskId);
      if (!mounted ||
          widget.initialTaskProjectId != projectId ||
          widget.initialTaskId != taskId) {
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectTaskDetailsPage(
              repository: repository, project: project, task: task),
        ),
      );
      widget.onInitialTaskOpened?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('任务加载失败：${userFacingError(error)}')));
        if (widget.initialTaskProjectId == projectId &&
            widget.initialTaskId == taskId) {
          widget.onInitialTaskOpened?.call();
        }
      }
    }
  }

  Future<void> _showInitialDocument(
      String documentId, List<Project> projects) async {
    try {
      final document = await repository.document(documentId);
      if (!mounted || widget.initialDocumentId != documentId) return;
      final project =
          projects.where((item) => item.id == document.projectId).firstOrNull ??
              await repository.project(document.projectId);
      if (!mounted || widget.initialDocumentId != documentId) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditorPage(
            repository: repository,
            document: document,
            projectName: project.name,
            collaboration: widget.documentCollaborationFactory?.call(document),
          ),
        ),
      );
      widget.onInitialDocumentOpened?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('文档加载失败：${userFacingError(error)}')));
        if (widget.initialDocumentId == documentId) {
          widget.onInitialDocumentOpened?.call();
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProjectsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId == null) _openedInitialProjectId = null;
    if (widget.initialTaskProjectId == null || widget.initialTaskId == null) {
      _openedInitialTaskKey = null;
    }
    if (widget.initialDocumentId == null) _openedInitialDocumentId = null;
    if (oldWidget.initialProjectId != widget.initialProjectId) {
      _openInitialProject(_allProjects);
    }
    if (oldWidget.initialTaskProjectId != widget.initialTaskProjectId ||
        oldWidget.initialTaskId != widget.initialTaskId) {
      _openInitialTask(_allProjects);
    }
    if (oldWidget.initialDocumentId != widget.initialDocumentId) {
      _openInitialDocument(_allProjects);
    }
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pollFallback() async {
    final session = widget.realtimeSession;
    if (!mounted || session == null || session.ready || _fallbackPollInFlight)
      return;
    _fallbackPollInFlight = true;
    try {
      await _refreshProjects();
    } catch (_) {
      // 项目缓存继续展示，下一周期再尝试同步。
    } finally {
      _fallbackPollInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        _projectList(context),
        Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
                heroTag: 'projects-create-project',
                onPressed: () => _createProject(context),
                tooltip: '新建项目',
                child: const Icon(Icons.create_new_folder))),
      ]);

  Widget _projectList(BuildContext context) {
    if (_loadingProjects && _allProjects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_projectsError != null && _allProjects.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text('项目加载失败：${userFacingError(_projectsError!)}'),
        TextButton.icon(
            onPressed: _reloadProjects,
            icon: const Icon(Icons.refresh),
            label: const Text('重试')),
      ]));
    }
    final keyword = _search.trim().toLowerCase();
    final projects = keyword.isEmpty
        ? _allProjects
        : _allProjects
            .where((project) => _projectSearchText(project).contains(keyword))
            .toList(growable: false);
    final hasFooter = _projectsError != null ||
        _nextProjectsCursor != null ||
        _loadingMoreProjects;
    final contentCount = projects.isEmpty ? 1 : projects.length;
    return RefreshIndicator(
        onRefresh: _refreshProjects,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
          itemCount: 1 + contentCount + (hasFooter ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: TextField(
                      controller: _searchController,
                      onChanged: _searchProjects,
                      decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: '搜索项目',
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchProjects('');
                                  },
                                  icon: const Icon(Icons.clear)),
                          border: const OutlineInputBorder())));
            }
            if (hasFooter && index == contentCount + 1) {
              return _projectListFooter();
            }
            if (projects.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child: Text(_loadingProjects
                          ? '正在加载项目'
                          : keyword.isEmpty
                              ? '暂无项目'
                              : '未找到匹配的项目')));
            }
            final project = projects[index - 1];
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: ProjectAvatar(
                repository: repository,
                project: project,
                serverUrl: widget.serverUrl,
                cacheScope: widget.cacheScope,
              ),
              title: Row(children: [
                Flexible(child: Text(project.name)),
                if (project.isPersonal) ...[
                  const SizedBox(width: 8),
                  const Chip(
                      visualDensity: VisualDensity.compact, label: Text('个人')),
                ]
              ]),
              subtitle: Text(project.description.isNotEmpty
                  ? project.description
                  : project.isPersonal
                      ? '仅自己可见的个人项目'
                      : '团队项目'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (project.taskCount case final count?) Text('$count 个任务'),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => _showTasks(project),
              onLongPress: () => _projectActions(context, project),
            );
          },
        ));
  }

  Widget _projectListFooter() {
    if (_projectsError != null) {
      final retryNext = _failedProjectsCursor != null;
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            Text(retryNext ? '加载下一页失败' : '刷新项目失败'),
            TextButton.icon(
              onPressed: () => _loadProjects(next: retryNext),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ]));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: OutlinedButton.icon(
        onPressed:
            _loadingMoreProjects ? null : () => _loadProjects(next: true),
        icon: _loadingMoreProjects
            ? const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.expand_more),
        label: Text(_loadingMoreProjects ? '正在加载' : '加载更多项目'),
      ),
    );
  }

  void _completeFailedInitialTargets() {
    final projectId = widget.initialProjectId;
    if (projectId != null &&
        projectId.isNotEmpty &&
        projectId != _openedInitialProjectId) {
      _openedInitialProjectId = projectId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.initialProjectId == projectId) {
          widget.onInitialProjectOpened?.call();
        }
      });
    }
    final taskProjectId = widget.initialTaskProjectId;
    final taskId = widget.initialTaskId;
    final taskKey = '$taskProjectId:$taskId';
    if (taskProjectId?.isNotEmpty == true &&
        taskId?.isNotEmpty == true &&
        taskKey != _openedInitialTaskKey) {
      _openedInitialTaskKey = taskKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.initialTaskProjectId == taskProjectId &&
            widget.initialTaskId == taskId) {
          widget.onInitialTaskOpened?.call();
        }
      });
    }
    final documentId = widget.initialDocumentId;
    if (documentId != null &&
        documentId.isNotEmpty &&
        documentId != _openedInitialDocumentId) {
      _openedInitialDocumentId = documentId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.initialDocumentId == documentId) {
          widget.onInitialDocumentOpened?.call();
        }
      });
    }
  }

  Future<void> _projectActions(BuildContext context, Project project) async {
    try {
      project = await repository.project(project.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('项目详情加载失败：${userFacingError(error)}')));
      }
      return;
    }
    if (!context.mounted) return;
    if (!project.canManage) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('只有项目所有者可管理项目')));
      return;
    }
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
      final updated = await _editProject(context, project);
      if (updated != null) _reloadProjects();
    }
  }

  Future<Project?> _editProject(BuildContext context, Project project) =>
      showDialog<Project>(
        context: context,
        builder: (context) => _ProjectEditDialog(
          repository: repository,
          project: project,
          serverUrl: widget.serverUrl,
          cacheScope: widget.cacheScope,
          imagePicker: widget.projectAvatarPicker ?? _pickProjectAvatar,
        ),
      );

  Future<Uint8List?> _pickProjectAvatar() async {
    final result =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    return result?.files.single.bytes;
  }

  Future<void> _createProject(BuildContext context) async {
    var groups = const <ChatConversation>[];
    try {
      groups = (await repository.conversations())
          .where((conversation) => conversation.type == 'group')
          .toList();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('群聊加载失败，将创建未关联群聊的项目：${userFacingError(error)}')));
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败：${userFacingError(error)}')));
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

  Future<void> _showTasks(Project project) async {
    try {
      project = await repository.project(project.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('项目详情加载失败：${userFacingError(error)}')));
      }
      return;
    }
    var keyword = '';
    var label = '';
    var status = '';
    var priority = 0;
    var initialTab = 0;
    final preferenceKey = _projectTaskViewPreferenceKey(project.id);
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getInt(preferenceKey);
      if (stored != null && stored >= 0 && stored < _projectTaskViewCount) {
        initialTab = stored;
      }
    } catch (_) {
      // 视图记忆不可用时仍正常打开项目工作区。
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setFilterState) => ProjectWorkspacePage(
            project: project,
            repository: repository,
            serverUrl: widget.serverUrl,
            cacheScope: widget.cacheScope,
            onEditProject: project.canManage
                ? () async {
                    final updated = await _editProject(context, project);
                    if (updated != null && context.mounted) {
                      project = updated;
                      setFilterState(() {});
                      _reloadProjects();
                    }
                  }
                : null,
            onCreateTask: () => _createTask(context, project,
                onChanged: () => setFilterState(() {})),
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
                  initialIndex: initialTab,
                  length: 7,
                  child: Column(children: [
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
                    TabBar(
                        isScrollable: true,
                        onTap: (index) async {
                          initialTab = index;
                          try {
                            final preferences =
                                await SharedPreferences.getInstance();
                            await preferences.setInt(preferenceKey, index);
                          } catch (_) {
                            // 视图记忆失败不影响当前切换。
                          }
                        },
                        tabs: const [
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
                      ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: snapshot.data!.isEmpty
                              ? 1
                              : snapshot.data!.length,
                          itemBuilder: (context, index) =>
                              snapshot.data!.isEmpty
                                  ? const SizedBox(
                                      height: 220,
                                      child: Center(child: Text('暂无匹配任务')))
                                  : _taskTile(
                                      context, project, snapshot.data![index],
                                      onChanged: () => setFilterState(() {}))),
                      _taskBoard(context, project, snapshot.data!,
                          onChanged: () => setFilterState(() {})),
                      ProjectTaskCalendarView(
                          tasks: snapshot.data!,
                          onOpenTask: (task) async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProjectTaskDetailsPage(
                                        repository: repository,
                                        project: project,
                                        task: task)));
                            if (context.mounted) setFilterState(() {});
                          }),
                      _taskGantt(context, project, snapshot.data!,
                          onChanged: () => setFilterState(() {})),
                      _documentsView(context, project),
                      _goalsView(context, project, snapshot.data!),
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

  Widget _taskTile(BuildContext context, Project project, ProjectTask task,
          {required VoidCallback onChanged}) =>
      ListTile(
        leading: IconButton(
            tooltip: '推进任务状态',
            onPressed: () =>
                _cycleTaskStatus(context, project, task, onChanged),
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
                await _editTask(context, project, task, onChanged);
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
                if (context.mounted) onChanged();
              }
            },
            itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑任务')),
                  PopupMenuItem(value: 'delete', child: Text('删除任务'))
                ]),
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ProjectTaskDetailsPage(
                      repository: repository, project: project, task: task)));
          if (context.mounted) onChanged();
        },
        onLongPress: () => _addComment(context, project, task),
      );

  Future<void> _editTask(BuildContext context, Project project,
      ProjectTask task, VoidCallback onChanged) async {
    final updated = await showProjectTaskEditorDialog(
      context,
      repository: repository,
      project: project,
      task: task,
    );
    if (updated != null && context.mounted) onChanged();
  }

  Widget _goalsView(
      BuildContext context, Project project, List<ProjectTask> tasks) {
    final summary = summarizeProjectTasks(tasks);
    final scheduled = tasks
        .where((task) => task.dueDate?.trim().isNotEmpty == true)
        .toList()
      ..sort((left, right) => (DateTime.tryParse(left.dueDate ?? '') ??
              DateTime(9999))
          .compareTo(DateTime.tryParse(right.dueDate ?? '') ?? DateTime(9999)));
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('目标概览',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              SizedBox.square(
                dimension: 74,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: summary.completionRatio,
                    strokeWidth: 8,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                  Text('${(summary.completionRatio * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('任务完成率',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('已完成 ${summary.completed} / 共 ${summary.total} 项'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        Chip(
                            avatar: const Icon(Icons.play_arrow, size: 16),
                            label: Text('进行中 ${summary.active}'),
                            visualDensity: VisualDensity.compact),
                        Chip(
                            avatar: const Icon(Icons.schedule, size: 16),
                            label: Text('待处理 ${summary.pending}'),
                            visualDensity: VisualDensity.compact),
                        if (summary.canceled > 0)
                          Chip(
                              avatar: const Icon(Icons.block, size: 16),
                              label: Text('已取消 ${summary.canceled}'),
                              visualDensity: VisualDensity.compact),
                      ]),
                    ]),
              ),
            ]),
          ),
        ),
        if (summary.overdue > 0) ...[
          const SizedBox(height: 10),
          Card(
            color: colors.errorContainer,
            child: ListTile(
              leading:
                  Icon(Icons.warning_amber, color: colors.onErrorContainer),
              title: Text('有 ${summary.overdue} 项任务已逾期',
                  style: TextStyle(color: colors.onErrorContainer)),
              subtitle: Text('打开任务列表可调整排期或状态',
                  style: TextStyle(color: colors.onErrorContainer)),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text('排期中的任务',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (scheduled.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('暂无排期任务')))
        else
          ...scheduled.take(8).map((task) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(task.status == 'done'
                    ? Icons.check_circle_outline
                    : Icons.event_note_outlined),
                title: Text(task.title),
                subtitle: Text(_taskMetadata(task),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(task.dueDate ?? ''),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProjectTaskDetailsPage(
                            repository: repository,
                            project: project,
                            task: task))),
              )),
      ],
    );
  }

  Widget _membersView(BuildContext context, Project project) =>
      FutureBuilder<List<ProjectMember>>(
          future: repository.projectMembers(project.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Text('成员加载失败：${userFacingError(snapshot.error!)}'));
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('授权群组加载失败：${userFacingError(error)}')));
      }
    }
  }

  Widget _documentsView(BuildContext context, Project project) =>
      _ProjectDocumentsView(
        repository: repository,
        project: project,
        documentCollaborationFactory: widget.documentCollaborationFactory,
        onDocumentActions: (document) =>
            _documentActions(context, project, document),
        onCreateDocument: () => _createDocument(context, project),
      );

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
      BuildContext context, Project project, List<ProjectTask> tasks,
      {required VoidCallback onChanged}) {
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
                                ...items.map((task) => _taskTile(
                                    context, project, task,
                                    onChanged: onChanged)),
                              ]))));
            }).toList()),
      ),
    );
  }

  Widget _taskGantt(
      BuildContext context, Project project, List<ProjectTask> tasks,
      {required VoidCallback onChanged}) {
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
                  onTap: () =>
                      _cycleTaskStatus(context, project, task, onChanged),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cycleTaskStatus(BuildContext context, Project project,
      ProjectTask task, VoidCallback onChanged) async {
    final next = task.status == 'todo'
        ? 'in_progress'
        : task.status == 'in_progress'
            ? 'done'
            : 'todo';
    await repository.updateTaskStatus(project.id, task.id, next);
    if (context.mounted) onChanged();
  }

  Future<void> _createTask(BuildContext context, Project project,
      {required VoidCallback onChanged}) async {
    List<ProjectMember> members;
    try {
      members = await repository.projectMembers(project.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('项目成员加载失败：${userFacingError(error)}')));
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
    unawaited(Future<void>.delayed(kThemeAnimationDuration, () {
      titleController.dispose();
      descriptionController.dispose();
      startController.dispose();
      dueController.dispose();
      labelsController.dispose();
      reminderController.dispose();
    }));
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
      if (context.mounted) onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建任务失败：${userFacingError(error)}')));
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

class _ProjectDocumentsView extends StatefulWidget {
  const _ProjectDocumentsView({
    required this.repository,
    required this.project,
    required this.documentCollaborationFactory,
    required this.onDocumentActions,
    required this.onCreateDocument,
  });

  final MagicChatRepository repository;
  final Project project;
  final DocumentCollaborationFactory? documentCollaborationFactory;
  final Future<void> Function(ProjectDocument document) onDocumentActions;
  final VoidCallback onCreateDocument;

  @override
  State<_ProjectDocumentsView> createState() => _ProjectDocumentsViewState();
}

class _ProjectDocumentsViewState extends State<_ProjectDocumentsView> {
  late Future<List<ProjectDocument>> _future =
      widget.repository.documents(widget.project.id);
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.repository.documents(widget.project.id);
    setState(() => _future = future);
    await future;
  }

  List<ProjectDocument> _filterDocuments(List<ProjectDocument> source) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return source;
    final byId = {for (final document in source) document.id: document};
    final included = <String>{
      for (final document in source)
        if (document.title.toLowerCase().contains(query)) document.id,
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final id in included.toList(growable: false)) {
        final parentId = byId[id]?.parentId;
        if (parentId != null && byId.containsKey(parentId)) {
          changed = included.add(parentId) || changed;
        }
      }
    }
    return source.where((document) => included.contains(document.id)).toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProjectDocument>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('文档加载失败，点击重试')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final documents = [..._filterDocuments(snapshot.data!)]
            ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
          final query = _query.trim();
          return Stack(children: [
            Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '搜索当前项目文档',
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear)),
                  ),
                ),
              ),
              Expanded(
                child: documents.isEmpty
                    ? Center(child: Text(query.isEmpty ? '暂无文档' : '未找到匹配文档'))
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          children: [
                            _LazyDocumentTree(
                              project: widget.project,
                              documents: documents,
                              repository: widget.repository,
                              parentId: null,
                              expandFolders: query.isNotEmpty,
                              documentCollaborationFactory:
                                  widget.documentCollaborationFactory,
                              onDocumentActions: widget.onDocumentActions,
                            ),
                          ],
                        ),
                      ),
              ),
            ]),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'projects-create-document',
                onPressed: widget.onCreateDocument,
                tooltip: '新建文档',
                child: const Icon(Icons.note_add_outlined),
              ),
            ),
          ]);
        },
      );
}

class _LazyDocumentTree extends StatelessWidget {
  const _LazyDocumentTree({
    required this.project,
    required this.documents,
    required this.repository,
    required this.parentId,
    required this.expandFolders,
    required this.documentCollaborationFactory,
    required this.onDocumentActions,
  });

  final Project project;
  final List<ProjectDocument> documents;
  final MagicChatRepository repository;
  final String? parentId;
  final bool expandFolders;
  final DocumentCollaborationFactory? documentCollaborationFactory;
  final Future<void> Function(ProjectDocument document) onDocumentActions;

  @override
  Widget build(BuildContext context) {
    final children = documents.where((item) => item.parentId == parentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final document in children)
          _LazyDocumentNode(
            key: ValueKey('lazy-document-${document.id}'),
            project: project,
            documents: documents,
            repository: repository,
            document: document,
            expandFolders: expandFolders,
            documentCollaborationFactory: documentCollaborationFactory,
            onDocumentActions: onDocumentActions,
          ),
      ],
    );
  }
}

class _LazyDocumentNode extends StatefulWidget {
  const _LazyDocumentNode({
    required this.project,
    required this.documents,
    required this.repository,
    required this.document,
    required this.expandFolders,
    required this.documentCollaborationFactory,
    required this.onDocumentActions,
    super.key,
  });

  final Project project;
  final List<ProjectDocument> documents;
  final MagicChatRepository repository;
  final ProjectDocument document;
  final bool expandFolders;
  final DocumentCollaborationFactory? documentCollaborationFactory;
  final Future<void> Function(ProjectDocument document) onDocumentActions;

  @override
  State<_LazyDocumentNode> createState() => _LazyDocumentNodeState();
}

class _LazyDocumentNodeState extends State<_LazyDocumentNode> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expandFolders;
  }

  @override
  void didUpdateWidget(covariant _LazyDocumentNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandFolders != widget.expandFolders) {
      _expanded = widget.expandFolders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    if (document.kind == 'folder') {
      final descendants = Padding(
        padding: const EdgeInsets.only(left: 16),
        child: _LazyDocumentTree(
          project: widget.project,
          documents: widget.documents,
          repository: widget.repository,
          parentId: document.id,
          expandFolders: widget.expandFolders,
          documentCollaborationFactory: widget.documentCollaborationFactory,
          onDocumentActions: widget.onDocumentActions,
        ),
      );
      if (widget.expandFolders) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onLongPress: () => widget.onDocumentActions(document),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(document.title),
                subtitle: const Text('目录'),
              ),
            ),
            descendants,
          ],
        );
      }
      return InkWell(
        onLongPress: () => widget.onDocumentActions(document),
        child: ExpansionTile(
          key: PageStorageKey(document.id),
          initiallyExpanded: widget.expandFolders,
          leading: const Icon(Icons.folder_outlined),
          title: Text(document.title),
          subtitle: const Text('目录'),
          onExpansionChanged: (expanded) =>
              setState(() => _expanded = expanded),
          // 后代树仅在用户展开目录后挂载，避免目录页首屏递归构建全部节点。
          children: _expanded ? [descendants] : const [],
        ),
      );
    }
    return ListTile(
      leading: Icon(document.documentType == 'markdown'
          ? Icons.code_outlined
          : Icons.description_outlined),
      title: Text(document.title),
      subtitle:
          Text(document.documentType == 'markdown' ? 'Markdown 文档' : '富文本文档'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditorPage(
            repository: widget.repository,
            document: document,
            projectName: widget.project.name,
            collaboration: widget.documentCollaborationFactory?.call(document),
          ),
        ),
      ),
      onLongPress: () => widget.onDocumentActions(document),
    );
  }
}

class _ProjectEditDialog extends StatefulWidget {
  const _ProjectEditDialog({
    required this.repository,
    required this.project,
    required this.imagePicker,
    this.serverUrl,
    this.cacheScope,
  });

  final MagicChatRepository repository;
  final Project project;
  final ProjectAvatarPicker imagePicker;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;

  @override
  State<_ProjectEditDialog> createState() => _ProjectEditDialogState();
}

class _ProjectEditDialogState extends State<_ProjectEditDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.project.name);
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.project.description);
  Uint8List? _avatar;
  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final source = await widget.imagePicker();
      if (source == null || !mounted) return;
      final avatar = const AvatarProcessor().process(source);
      setState(() {
        _avatar = avatar;
        _error = '';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = '头像处理失败：${userFacingError(error)}');
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (!widget.project.isPersonal && name.isEmpty) {
      setState(() => _error = '项目名称不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      var updated = await widget.repository.updateProject(
        widget.project.id,
        name: widget.project.isPersonal ? null : name,
        description: _descriptionController.text.trim(),
      );
      if (_avatar != null) {
        updated = await widget.repository.uploadProjectAvatar(
          widget.project.id,
          AttachmentUpload(
            path: '',
            name: 'project-avatar.webp',
            mimeType: 'image/webp',
            bytes: _avatar,
          ),
        );
      }
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败：${userFacingError(error)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: const Text('修改项目信息'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _avatar == null
                        ? ProjectAvatar(
                            repository: widget.repository,
                            project: widget.project,
                            serverUrl: widget.serverUrl,
                            cacheScope: widget.cacheScope,
                            radius: 32,
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(_avatar!,
                                width: 64, height: 64, fit: BoxFit.cover),
                          ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!widget.project.isPersonal)
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _pickAvatar,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(_avatar == null ? '选择项目头像' : '重新选择'),
                            )
                          else
                            const Text('个人项目头像跟随账户头像'),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    enabled: !_saving && !widget.project.isPersonal,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: '项目名称'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    enabled: !_saving,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                        labelText: '项目描述', hintText: '暂无说明'),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_error,
                        key: const ValueKey('project-edit-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('保存')),
          ],
        ),
      );
}

String _projectSearchText(Project project) {
  final source = '${project.name} ${project.description}'.trim();
  final pinyin = PinyinHelper.getPinyinE(source,
      separator: '', format: PinyinFormat.WITHOUT_TONE, defPinyin: '#');
  return '$source $pinyin'.toLowerCase();
}
