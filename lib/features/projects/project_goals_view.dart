import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/project_goals_repository.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../domain/project_goal.dart';
import '../shared/user_facing_error.dart';

class ProjectGoalsView extends StatefulWidget {
  const ProjectGoalsView({
    required this.repository,
    required this.project,
    this.goalsRepository,
    super.key,
  });

  final MagicChatRepository repository;
  final Project project;
  final ProjectGoalsRepository? goalsRepository;

  @override
  State<ProjectGoalsView> createState() => _ProjectGoalsViewState();
}

class _ProjectGoalsViewState extends State<ProjectGoalsView> {
  late ProjectGoalsRepository _repository;
  late Future<List<ProjectGoal>> _goals;
  String _status = '';
  final _busyGoalIds = <String>{};
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.goalsRepository ?? ProjectGoalsRepository(widget.repository);
    _goals = _repository.list(widget.project.id);
  }

  @override
  void didUpdateWidget(covariant ProjectGoalsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.goalsRepository != widget.goalsRepository ||
        oldWidget.repository != widget.repository) {
      _repository =
          widget.goalsRepository ?? ProjectGoalsRepository(widget.repository);
      _goals = _repository.list(widget.project.id);
    }
  }

  Future<void> _reload() async {
    final future = _repository.list(widget.project.id);
    setState(() => _goals = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProjectGoal>>(
        future: _goals,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 10),
                Text('目标加载失败：${userFacingError(snapshot.error!)}'),
                TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试')),
              ]),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final goals = snapshot.data!;
          final visible = _status.isEmpty
              ? goals
              : goals.where((goal) => goal.status == _status).toList();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('项目目标',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text('目标由项目任务承载，其他客户端会显示为带标签的任务。',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
                    label: const Text('新建目标'),
                  ),
                ]),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '', label: Text('全部')),
                      ButtonSegment(value: 'todo', label: Text('待开始')),
                      ButtonSegment(value: 'in_progress', label: Text('进行中')),
                      ButtonSegment(value: 'done', label: Text('已完成')),
                      ButtonSegment(value: 'canceled', label: Text('已取消')),
                    ],
                    selected: {_status},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) =>
                        setState(() => _status = values.single),
                  ),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  _GoalEmptyState(filtered: _status.isNotEmpty)
                else
                  ...visible.map(_goalCard),
              ],
            ),
          );
        },
      );

  Widget _goalCard(ProjectGoal goal) {
    final busy = _busyGoalIds.contains(goal.id);
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('project-goal-${goal.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_statusIcon(goal.status),
              color: _statusColor(goal.status, colors)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (goal.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(goal.description,
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Chip(
                      label: Text(_statusLabel(goal.status)),
                      visualDensity: VisualDensity.compact),
                  Chip(
                      label: Text('优先级 ${_priorityLabel(goal.priority)}'),
                      visualDensity: VisualDensity.compact),
                  if (goal.dueDate != null)
                    Chip(
                        avatar: const Icon(Icons.event_outlined, size: 16),
                        label: Text('目标日 ${goal.dueDate}'),
                        visualDensity: VisualDensity.compact),
                  ...goal.labels.take(3).map((label) => Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact)),
                ]),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            PopupMenuButton<String>(
              tooltip: '更新目标状态',
              icon: const Icon(Icons.flag_outlined),
              onSelected: (status) => _updateStatus(goal, status),
              itemBuilder: (context) => projectGoalStatuses
                  .map((status) => PopupMenuItem(
                      value: status, child: Text(_statusLabel(status))))
                  .toList(),
            ),
            PopupMenuButton<String>(
              tooltip: '目标操作',
              onSelected: (action) {
                if (action == 'edit') {
                  unawaited(_edit(goal));
                } else if (action == 'delete') {
                  unawaited(_delete(goal));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑目标')),
                PopupMenuItem(value: 'delete', child: Text('删除目标')),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _create() async {
    final input = await showDialog<ProjectGoalInput>(
        context: context, builder: (_) => const _ProjectGoalEditorDialog());
    if (input == null || !mounted) return;
    setState(() => _creating = true);
    try {
      await _repository.create(widget.project.id, input);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('目标已创建')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建目标失败：${userFacingError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _edit(ProjectGoal goal) async {
    final input = await showDialog<ProjectGoalInput>(
      context: context,
      builder: (_) => _ProjectGoalEditorDialog(goal: goal),
    );
    if (input == null || !mounted) return;
    await _mutate(goal, () => _repository.update(goal, input), '目标已更新');
  }

  Future<void> _updateStatus(ProjectGoal goal, String status) async =>
      _mutate(goal, () => _repository.updateStatus(goal, status), '目标状态已更新');

  Future<void> _delete(ProjectGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除目标？'),
        content: Text('将删除“${goal.title}”以及对应的项目任务，此操作无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(goal, () => _repository.delete(goal), '目标已删除');
  }

  Future<void> _mutate(ProjectGoal goal, Future<Object?> Function() operation,
      String success) async {
    setState(() => _busyGoalIds.add(goal.id));
    try {
      await operation();
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('目标操作失败：${userFacingError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _busyGoalIds.remove(goal.id));
    }
  }
}

class _GoalEmptyState extends StatelessWidget {
  const _GoalEmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 46),
        child: Column(children: [
          Icon(Icons.flag_outlined,
              size: 44, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          Text(filtered ? '当前状态下没有目标' : '还没有项目目标'),
          if (!filtered)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('创建一个可跟踪状态和目标日期的项目目标。'),
            ),
        ]),
      );
}

class _ProjectGoalEditorDialog extends StatefulWidget {
  const _ProjectGoalEditorDialog({this.goal});

  final ProjectGoal? goal;

  @override
  State<_ProjectGoalEditorDialog> createState() =>
      _ProjectGoalEditorDialogState();
}

class _ProjectGoalEditorDialogState extends State<_ProjectGoalEditorDialog> {
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _description =
      TextEditingController(text: widget.goal?.description ?? '');
  late final _startDate =
      TextEditingController(text: widget.goal?.startDate ?? '');
  late final _dueDate = TextEditingController(text: widget.goal?.dueDate ?? '');
  late final _labels =
      TextEditingController(text: widget.goal?.labels.join(', ') ?? '');
  late String _status = widget.goal?.status ?? 'todo';
  late int _priority = widget.goal?.priority ?? 2;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _startDate.dispose();
    _dueDate.dispose();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.goal == null ? '新建目标' : '编辑目标'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                key: const ValueKey('project-goal-title'),
                controller: _title,
                autofocus: true,
                maxLength: 240,
                decoration: const InputDecoration(labelText: '目标名称'),
              ),
              TextField(
                key: const ValueKey('project-goal-description'),
                controller: _description,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '目标说明', hintText: '说明预期结果或验收标准'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: '状态'),
                items: projectGoalStatuses
                    .map((status) => DropdownMenuItem(
                        value: status, child: Text(_statusLabel(status))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('低')),
                  DropdownMenuItem(value: 2, child: Text('中')),
                  DropdownMenuItem(value: 3, child: Text('高')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              TextField(
                key: const ValueKey('project-goal-start-date'),
                controller: _startDate,
                decoration: const InputDecoration(
                    labelText: '开始日期', hintText: 'YYYY-MM-DD'),
              ),
              TextField(
                key: const ValueKey('project-goal-due-date'),
                controller: _dueDate,
                decoration: const InputDecoration(
                    labelText: '目标日期', hintText: 'YYYY-MM-DD'),
              ),
              TextField(
                key: const ValueKey('project-goal-labels'),
                controller: _labels,
                decoration: const InputDecoration(labelText: '其他标签（逗号分隔）'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: _submit,
              child: Text(widget.goal == null ? '创建' : '保存')),
        ],
      );

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入目标名称');
      return;
    }
    final startDate = _date(_startDate.text);
    final dueDate = _date(_dueDate.text);
    if ((_startDate.text.trim().isNotEmpty && startDate == null) ||
        (_dueDate.text.trim().isNotEmpty && dueDate == null)) {
      setState(() => _error = '日期格式应为 YYYY-MM-DD');
      return;
    }
    if (startDate != null &&
        dueDate != null &&
        startDate.compareTo(dueDate) > 0) {
      setState(() => _error = '开始日期不能晚于目标日期');
      return;
    }
    Navigator.pop(
      context,
      ProjectGoalInput(
        title: title,
        description: _description.text.trim(),
        status: _status,
        priority: _priority,
        startDate: startDate,
        dueDate: dueDate,
        labels: _labels.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false),
      ),
    );
  }

  String? _date(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final parsed = DateTime.tryParse(normalized);
    return parsed != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalized)
        ? normalized
        : null;
  }
}

String _statusLabel(String status) => switch (status) {
      'todo' => '待开始',
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

IconData _statusIcon(String status) => switch (status) {
      'in_progress' => Icons.play_circle_outline,
      'done' => Icons.check_circle_outline,
      'canceled' => Icons.cancel_outlined,
      _ => Icons.flag_outlined,
    };

Color _statusColor(String status, ColorScheme colors) => switch (status) {
      'done' => Colors.green.shade700,
      'canceled' => colors.outline,
      'in_progress' => colors.primary,
      _ => colors.secondary,
    };
