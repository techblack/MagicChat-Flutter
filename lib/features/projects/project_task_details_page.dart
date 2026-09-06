import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../messages/send_card_dialog.dart';
import '../shared/user_facing_error.dart';

class ProjectTaskDetailsPage extends StatefulWidget {
  const ProjectTaskDetailsPage(
      {required this.repository,
      required this.project,
      required this.task,
      super.key});

  final MagicChatRepository repository;
  final Project project;
  final ProjectTask task;

  @override
  State<ProjectTaskDetailsPage> createState() => _ProjectTaskDetailsPageState();
}

class _ProjectTaskDetailsPageState extends State<ProjectTaskDetailsPage> {
  late Future<List<ProjectTaskActivity>> _activities;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _activities =
        widget.repository.taskActivities(widget.project.id, widget.task.id);
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final content = _comment.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final activity = await widget.repository
          .addTaskComment(widget.project.id, widget.task.id, content);
      final current = await _activities;
      if (!mounted) return;
      _comment.clear();
      setState(() {
        _activities = Future.value([...current, activity]);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('评论失败：${userFacingError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendCard() => showDialog<void>(
        context: context,
        builder: (_) => SendCardDialog(
          repository: widget.repository,
          cardTitle: widget.task.title,
          cardDescription: '任务 · ${widget.project.name}',
          onSend: (conversationId) => widget.repository.sendEntityCard(
            conversationId,
            entityType: 'task',
            entityId: widget.task.id,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.task.title),
          actions: [
            IconButton(
                key: const ValueKey('task-send-card'),
                tooltip: '发送到会话',
                onPressed: _sendCard,
                icon: const Icon(Icons.send_outlined)),
          ],
        ),
        body: Column(children: [
          Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
            _taskSummary(context),
            const SizedBox(height: 20),
            Text('任务动态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<ProjectTaskActivity>>(
                future: _activities,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Card(
                        child: ListTile(
                            leading: const Icon(Icons.error_outline),
                            title: const Text('任务动态加载失败'),
                            subtitle: Text(userFacingError(snapshot.error!)),
                            trailing: IconButton(
                                tooltip: '重试',
                                onPressed: () => setState(() {
                                      _activities = widget.repository
                                          .taskActivities(widget.project.id,
                                              widget.task.id);
                                    }),
                                icon: const Icon(Icons.refresh))));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Card(
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('暂无任务动态')));
                  }
                  return Column(
                      children: snapshot.data!
                          .map((activity) => _activityTile(context, activity))
                          .toList());
                })
          ])),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: TextField(
                                controller: _comment,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                    labelText: '发表评论',
                                    hintText: '输入评论，支持 Markdown',
                                    border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            tooltip: '发送评论',
                            onPressed: _sending ? null : _sendComment,
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.send_outlined))
                      ])))
        ]),
      );

  Widget _taskSummary(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                  avatar: const Icon(Icons.adjust, size: 16),
                  label: Text(_statusLabel(widget.task.status))),
              Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 16),
                  label: Text('${_priorityLabel(widget.task.priority)}优先级')),
              if (widget.task.assignee case final assignee?)
                Chip(
                    avatar: const Icon(Icons.person_outline, size: 16),
                    label: Text(assignee.displayName))
            ]),
            if (widget.task.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              MarkdownBody(
                  data: widget.task.description,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))),
            ],
            if (widget.task.startDate != null ||
                widget.task.dueDate != null) ...[
              const SizedBox(height: 12),
              Text(
                  '排期：${widget.task.startDate ?? '未设置'} → ${widget.task.dueDate ?? '未设置'}')
            ],
            if (widget.task.reminder case final reminder?
                when reminder.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notifications_active_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_reminderSummary(reminder)))
              ])
            ],
            if (widget.task.labels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                  spacing: 6,
                  children: widget.task.labels
                      .map((label) => Chip(label: Text(label)))
                      .toList())
            ]
          ])));

  Widget _activityTile(BuildContext context, ProjectTaskActivity activity) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(
                          radius: 16,
                          child: Text(
                              activity.actor.displayName.characters.first)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              '${activity.actor.displayName} ${_activitySummary(activity)}')),
                      Text(_formatTime(activity.createdAt),
                          style: Theme.of(context).textTheme.bodySmall)
                    ]),
                    if (activity.type == 'commented' &&
                        activity.content.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8)),
                          child: MarkdownBody(data: activity.content))
                    ]
                  ])));

  String _activitySummary(ProjectTaskActivity activity) =>
      switch (activity.type) {
        'created' => '创建了任务',
        'commented' => '发表了评论',
        _ when activity.changes.isEmpty => '修改了任务',
        _ =>
          '修改了${activity.changes.map((item) => _fieldLabel(item.field)).join('、')}',
      };

  String _fieldLabel(String field) => switch (field) {
        'assignee' => '负责人',
        'description' => '详细内容',
        'due_date' => '截止日期',
        'labels' => '标签',
        'priority' => '优先级',
        'reminder' => '提醒时间',
        'start_date' => '开始日期',
        'status' => '状态',
        'title' => '标题',
        _ => '任务',
      };

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

  String _reminderSummary(Map<String, dynamic> reminder) {
    final mode = reminder['mode'];
    String summary;
    if (mode == 'once') {
      final at = reminder['at'];
      final date = at is String ? DateTime.tryParse(at) : null;
      summary = date == null ? '一次性提醒' : '一次性提醒 · ${_formatTime(at)}';
    } else {
      final frequency = reminder['frequency'];
      final time = reminder['time'] is String ? reminder['time'] as String : '';
      if (frequency == 'weekly') {
        final days = reminder['weekdays'] is List
            ? (reminder['weekdays'] as List)
                .whereType<num>()
                .map((day) => _weekdayLabel(day.toInt()))
                .where((day) => day.isNotEmpty)
                .join('、')
            : '';
        summary = '每周${days.isEmpty ? '' : days} $time'.trim();
      } else if (frequency == 'monthly') {
        final day = (reminder['day_of_month'] as num?)?.toInt();
        summary = '每月${day == null ? '' : ' $day 日'} $time'.trim();
      } else {
        summary = '每天 $time'.trim();
      }
      if (summary.isEmpty) summary = '周期性提醒';
    }
    final paused = widget.task.status == 'done' ||
        widget.task.status == 'canceled' ||
        reminder['state'] == 'paused';
    final state = reminder['state'];
    if (paused) return '已暂停 · $summary';
    if (state == 'fired') return '已提醒 · $summary';
    if (state == 'expired') return '已过期 · $summary';
    return summary;
  }

  String _weekdayLabel(int day) => switch (day) {
        1 => '一',
        2 => '二',
        3 => '三',
        4 => '四',
        5 => '五',
        6 => '六',
        7 => '日',
        _ => '',
      };

  String _formatTime(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }
}
