import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/user_facing_error.dart';

Future<ProjectTask?> showProjectTaskEditorDialog(
  BuildContext context, {
  required MagicChatRepository repository,
  required Project project,
  required ProjectTask task,
}) =>
    showDialog<ProjectTask>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProjectTaskEditorDialog(
        repository: repository,
        project: project,
        task: task,
      ),
    );

class ProjectTaskEditorDialog extends StatefulWidget {
  const ProjectTaskEditorDialog({
    required this.repository,
    required this.project,
    required this.task,
    super.key,
  });

  final MagicChatRepository repository;
  final Project project;
  final ProjectTask task;

  @override
  State<ProjectTaskEditorDialog> createState() =>
      _ProjectTaskEditorDialogState();
}

class _ProjectTaskEditorDialogState extends State<ProjectTaskEditorDialog> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _description = TextEditingController(
    text: widget.task.description,
  );
  late final _startDate = TextEditingController(
    text: widget.task.startDate ?? '',
  );
  late final _dueDate = TextEditingController(text: widget.task.dueDate ?? '');
  late final _labels = TextEditingController(
    text: widget.task.labels.join(', '),
  );
  late final _reminderAt = TextEditingController(
    text: '${widget.task.reminder?['at'] ?? ''}',
  );
  late final _reminderTime = TextEditingController(
    text: '${widget.task.reminder?['time'] ?? '09:00'}',
  );
  late final _reminderWeekdays = TextEditingController(
    text: (widget.task.reminder?['weekdays'] as List?)
            ?.whereType<num>()
            .map((day) => day.toInt())
            .join(', ') ??
        '1',
  );
  late final _reminderDayOfMonth = TextEditingController(
    text: '${widget.task.reminder?['day_of_month'] ?? 1}',
  );
  late final _reminderTimezone = TextEditingController(
    text: '${widget.task.reminder?['timezone'] ?? 'Asia/Shanghai'}',
  );
  late String _status = widget.task.status;
  late int _priority = widget.task.priority;
  late String _assigneeUserId = widget.task.assigneeUserId ?? '';
  late String _reminderMode = widget.task.reminder == null
      ? 'none'
      : '${widget.task.reminder!['mode'] ?? 'once'}';
  late String _reminderFrequency =
      '${widget.task.reminder?['frequency'] ?? 'daily'}';
  late final String _initialSignature;
  List<ProjectMember> _members = const [];
  Object? _membersError;
  String? _saveError;
  bool _loadingMembers = true;
  bool _saving = false;
  bool _confirmingClose = false;
  bool _allowPop = false;

  bool get _dirty => _signature(_buildUpdate()) != _initialSignature;

  @override
  void initState() {
    super.initState();
    _initialSignature = _signature(_buildUpdate());
    for (final controller in _controllers) {
      controller.addListener(_onFormChanged);
    }
    _loadMembers();
  }

  List<TextEditingController> get _controllers => [
        _title,
        _description,
        _startDate,
        _dueDate,
        _labels,
        _reminderAt,
        _reminderTime,
        _reminderWeekdays,
        _reminderDayOfMonth,
        _reminderTimezone,
      ];

  void _onFormChanged() {
    if (mounted) setState(() => _saveError = null);
  }

  Future<void> _loadMembers() async {
    try {
      final members = await widget.repository.projectMembers(widget.project.id);
      if (!mounted) return;
      setState(() {
        _members = members
            .where(
              (member) => member.status.isEmpty || member.status == 'active',
            )
            .toList(growable: false);
        _membersError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _membersError = error);
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  List<ProjectMember> get _memberOptions {
    final values = [..._members];
    final assignee = widget.task.assignee;
    if (assignee != null && !values.any((member) => member.id == assignee.id)) {
      values.insert(
        0,
        ProjectMember(
          id: assignee.id,
          name: assignee.name,
          nickname: assignee.nickname,
          avatar: assignee.avatar,
          displayNameOverride: assignee.displayName,
        ),
      );
    }
    return values;
  }

  Future<void> _save() async {
    if (_saving) return;
    final update = _buildUpdate();
    final validation = _validate(update);
    if (validation != null) {
      setState(() => _saveError = validation);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final updated = await widget.repository.updateTask(
        widget.project.id,
        widget.task.id,
        update,
      );
      if (mounted) _close(updated);
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError =
              '保存任务失败：${userFacingError(error, fallback: '请稍后重试')}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestClose() async {
    if (_saving || _confirmingClose) return;
    if (!_dirty) {
      _close();
      return;
    }
    _confirmingClose = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存修改？'),
        content: const Text('任务内容尚未保存，返回后本次修改将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _confirmingClose = false;
    if (discard == true && mounted) _close();
  }

  void _close([ProjectTask? result]) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  ProjectTaskUpdate _buildUpdate() {
    final labels = <String>[];
    final seen = <String>{};
    for (final value in _labels.text.split(',')) {
      final label = value.trim();
      if (label.isNotEmpty && seen.add(label.toLowerCase())) labels.add(label);
    }
    return ProjectTaskUpdate(
      title: _title.text.trim(),
      description: _description.text,
      status: _status,
      priority: _priority,
      startDate: _emptyToNull(_startDate.text),
      dueDate: _emptyToNull(_dueDate.text),
      labels: labels,
      assigneeUserId: _assigneeUserId.isEmpty ? null : _assigneeUserId,
      reminder: _buildReminder(),
    );
  }

  Map<String, dynamic>? _buildReminder() {
    if (_reminderMode == 'none') return null;
    final timezone = _reminderTimezone.text.trim();
    if (_reminderMode == 'once') {
      return {
        'mode': 'once',
        'at': _reminderAt.text.trim(),
        'timezone': timezone,
      };
    }
    return {
      'mode': 'recurring',
      'frequency': _reminderFrequency,
      'time': _reminderTime.text.trim(),
      'timezone': timezone,
      if (_reminderFrequency == 'weekly')
        'weekdays': _reminderWeekdays.text
            .split(',')
            .map((day) => int.tryParse(day.trim()))
            .whereType<int>()
            .toSet()
            .toList()
          ..sort(),
      if (_reminderFrequency == 'monthly')
        'day_of_month': int.tryParse(_reminderDayOfMonth.text.trim()),
    };
  }

  String? _validate(ProjectTaskUpdate update) {
    if (update.title.isEmpty || update.title.characters.length > 240) {
      return '标题长度必须为 1 到 240 个字符';
    }
    if (!_validDate(update.startDate) || !_validDate(update.dueDate)) {
      return '日期必须使用 YYYY-MM-DD 格式';
    }
    if (update.startDate != null &&
        update.dueDate != null &&
        update.startDate!.compareTo(update.dueDate!) > 0) {
      return '开始日期不能晚于截止日期';
    }
    if (update.labels.length > 20) return '标签最多设置 20 个';
    if (update.labels.any((label) => label.characters.length > 32)) {
      return '单个标签不能超过 32 个字符';
    }
    final reminder = update.reminder;
    if (reminder == null) return null;
    if ((reminder['timezone'] as String).isEmpty) return '提醒时区不能为空';
    if (reminder['mode'] == 'once') {
      return DateTime.tryParse('${reminder['at']}') == null
          ? '一次性提醒时间必须使用有效的 ISO-8601 格式'
          : null;
    }
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
        .hasMatch('${reminder['time']}')) {
      return '周期提醒时间必须使用 HH:mm 格式';
    }
    if (reminder['frequency'] == 'weekly') {
      final weekdays = reminder['weekdays'] as List<int>;
      if (weekdays.isEmpty || weekdays.any((day) => day < 1 || day > 7)) {
        return '每周提醒需设置 1 到 7 的星期数字';
      }
    }
    if (reminder['frequency'] == 'monthly') {
      final day = reminder['day_of_month'];
      if (day is! int || day < 1 || day > 31) return '每月提醒日期必须为 1 到 31';
    }
    return null;
  }

  bool _validDate(String? value) =>
      value == null ||
      (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
          DateTime.tryParse(value) != null);

  String? _emptyToNull(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _signature(ProjectTaskUpdate update) => jsonEncode({
        'title': update.title,
        'description': update.description,
        'status': update.status,
        'priority': update.priority,
        'start_date': update.startDate,
        'due_date': update.dueDate,
        'labels': update.labels,
        'assignee_user_id': update.assigneeUserId,
        'reminder': update.reminder,
      });

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_onFormChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestClose();
        },
        child: AlertDialog(
          title: const Text('编辑任务'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _title,
                    autofocus: true,
                    maxLength: 240,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  TextField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 8,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '描述',
                      hintText: '支持 Markdown',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: '状态'),
                    items: const [
                      DropdownMenuItem(value: 'todo', child: Text('待处理')),
                      DropdownMenuItem(
                          value: 'in_progress', child: Text('进行中')),
                      DropdownMenuItem(value: 'done', child: Text('已完成')),
                      DropdownMenuItem(value: 'canceled', child: Text('已取消')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _status = value ?? _status),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: '优先级'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('低')),
                      DropdownMenuItem(value: 2, child: Text('中')),
                      DropdownMenuItem(value: 3, child: Text('高')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) =>
                            setState(() => _priority = value ?? _priority),
                  ),
                  TextField(
                    controller: _startDate,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '开始日期（YYYY-MM-DD）',
                    ),
                  ),
                  TextField(
                    controller: _dueDate,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: '截止日期（YYYY-MM-DD）',
                    ),
                  ),
                  TextField(
                    controller: _labels,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('task-assignee-$_assigneeUserId'),
                    initialValue: _assigneeUserId,
                    decoration: const InputDecoration(labelText: '负责人'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('未分配')),
                      ..._memberOptions.map(
                        (member) => DropdownMenuItem(
                          value: member.id,
                          child: Text(
                            member.email.isEmpty
                                ? member.displayName
                                : '${member.displayName} · ${member.email}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: _saving || _loadingMembers
                        ? null
                        : (value) =>
                            setState(() => _assigneeUserId = value ?? ''),
                  ),
                  if (_loadingMembers) const LinearProgressIndicator(),
                  if (_membersError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _loadingMembers = true;
                            _membersError = null;
                          });
                          _loadMembers();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          '项目成员加载失败：${userFacingError(_membersError!)}，点击重试',
                        ),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _reminderMode,
                    decoration: const InputDecoration(labelText: '提醒模式'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('不提醒')),
                      DropdownMenuItem(value: 'once', child: Text('一次性')),
                      DropdownMenuItem(value: 'recurring', child: Text('周期性')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(
                              () => _reminderMode = value ?? _reminderMode,
                            ),
                  ),
                  if (_reminderMode == 'once')
                    TextField(
                      controller: _reminderAt,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: '提醒时间（ISO-8601）',
                      ),
                    ),
                  if (_reminderMode == 'recurring') ...[
                    DropdownButtonFormField<String>(
                      initialValue: _reminderFrequency,
                      decoration: const InputDecoration(labelText: '重复频率'),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('每天')),
                        DropdownMenuItem(value: 'weekly', child: Text('每周')),
                        DropdownMenuItem(value: 'monthly', child: Text('每月')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                                () => _reminderFrequency =
                                    value ?? _reminderFrequency,
                              ),
                    ),
                    TextField(
                      controller: _reminderTime,
                      enabled: !_saving,
                      decoration:
                          const InputDecoration(labelText: '提醒时间（HH:mm）'),
                    ),
                    if (_reminderFrequency == 'weekly')
                      TextField(
                        controller: _reminderWeekdays,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: '重复星期（1-7，逗号分隔）',
                        ),
                      ),
                    if (_reminderFrequency == 'monthly')
                      TextField(
                        controller: _reminderDayOfMonth,
                        enabled: !_saving,
                        decoration:
                            const InputDecoration(labelText: '每月日期（1-31）'),
                      ),
                  ],
                  if (_reminderMode != 'none')
                    TextField(
                      controller: _reminderTimezone,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: '时区'),
                    ),
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _saveError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _requestClose,
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saveError == null ? '保存' : '重试保存'),
            ),
          ],
        ),
      );
}
