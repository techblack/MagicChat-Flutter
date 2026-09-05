import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// 任务月历视图，与 Web/Desktop 的日期范围和未排期任务语义保持一致。
class ProjectTaskCalendarView extends StatefulWidget {
  const ProjectTaskCalendarView({
    required this.tasks,
    required this.onOpenTask,
    this.initialMonth,
    this.currentDate,
    super.key,
  });

  final List<ProjectTask> tasks;
  final ValueChanged<ProjectTask> onOpenTask;
  final DateTime? initialMonth;
  final DateTime? currentDate;

  @override
  State<ProjectTaskCalendarView> createState() =>
      _ProjectTaskCalendarViewState();
}

class _ProjectTaskCalendarViewState extends State<ProjectTaskCalendarView> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = _monthStart(widget.initialMonth ?? DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) {
      return const Center(child: Text('暂无任务'));
    }
    final unscheduled =
        widget.tasks.where((task) => _dateRange(task) == null).toList();
    final days = _calendarDays(_visibleMonth);
    final tasksByDate = _tasksByDate(widget.tasks, days);
    final today = _dateOnly(widget.currentDate ?? DateTime.now());
    final todayKey = _dateKey(today);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (unscheduled.isNotEmpty) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('未设置日期'),
              trailing: Badge(label: Text('${unscheduled.length}')),
              children: unscheduled
                  .map((task) => ListTile(
                        leading: Icon(_statusIcon(task.status),
                            color: _statusColor(context, task.status)),
                        title: Text(task.title),
                        subtitle: Text(
                            '${_statusLabel(task.status)} · ${_priorityLabel(task.priority)}优先级'),
                        onTap: () => widget.onOpenTask(task),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _monthHeader(context),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                    children: _weekdayLabels
                        .map((label) => Expanded(
                            child: Center(
                                child: Text('周$label',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall))))
                        .toList()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, mainAxisExtent: 84),
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final date = days[index];
                    final key = _dateKey(date);
                    final dateTasks = tasksByDate[key] ?? const [];
                    final inMonth = date.month == _visibleMonth.month;
                    final isToday = key == todayKey;
                    return Container(
                      margin: const EdgeInsets.all(1),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: isToday
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: .5)
                              : !inMonth
                                  ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: .35)
                                  : null,
                          border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${date.month}/${date.day}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: inMonth
                                            ? null
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant)),
                            const SizedBox(height: 3),
                            ...dateTasks.take(3).map((task) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: InkWell(
                                    onTap: () => widget.onOpenTask(task),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3, vertical: 2),
                                      decoration: BoxDecoration(
                                          color:
                                              _statusColor(context, task.status)
                                                  .withValues(alpha: .16),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: Text(task.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall),
                                    ),
                                  ),
                                )),
                            if (dateTasks.length > 3)
                              Text('+${dateTasks.length - 3} 项',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                          ]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _monthHeader(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(children: [
          IconButton(
              tooltip: '上个月',
              onPressed: () => setState(() => _visibleMonth =
                  DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1)),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: Center(
                  child: Text(
                      '${_visibleMonth.year} 年 ${_visibleMonth.month} 月',
                      style: Theme.of(context).textTheme.titleMedium))),
          IconButton(
              tooltip: '下个月',
              onPressed: () => setState(() => _visibleMonth =
                  DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1)),
              icon: const Icon(Icons.chevron_right)),
          TextButton(
              onPressed: () => setState(() => _visibleMonth =
                  _monthStart(widget.currentDate ?? DateTime.now())),
              child: const Text('今天')),
        ]),
      );
}

DateTime _monthStart(DateTime date) => DateTime(date.year, date.month, 1);

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

List<DateTime> _calendarDays(DateTime month) {
  final first = _monthStart(month);
  final mondayOffset = (first.weekday - DateTime.monday) % 7;
  final start = first.subtract(Duration(days: mondayOffset));
  return List.generate(42, (index) => start.add(Duration(days: index)));
}

({DateTime start, DateTime end})? _dateRange(ProjectTask task) {
  final start = _parseDate(task.startDate);
  final due = _parseDate(task.dueDate);
  if (start == null && due == null) return null;
  final first = start ?? due!;
  final last = due ?? start!;
  return first.isBefore(last)
      ? (start: first, end: last)
      : (start: last, end: first);
}

DateTime? _parseDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1], parts[2]);
  return date.year == parts[0] && date.month == parts[1] && date.day == parts[2]
      ? date
      : null;
}

Map<String, List<ProjectTask>> _tasksByDate(
    List<ProjectTask> tasks, List<DateTime> days) {
  final result = <String, List<ProjectTask>>{};
  final first = days.first;
  final last = days.last;
  for (final task in tasks) {
    final range = _dateRange(task);
    if (range == null ||
        range.end.isBefore(first) ||
        range.start.isAfter(last)) {
      continue;
    }
    var date = range.start.isBefore(first) ? first : range.start;
    final end = range.end.isAfter(last) ? last : range.end;
    while (!date.isAfter(end)) {
      result.putIfAbsent(_dateKey(date), () => []).add(task);
      date = date.add(const Duration(days: 1));
    }
  }
  for (final values in result.values) {
    values.sort((a, b) {
      final status = _statusOrder(a.status).compareTo(_statusOrder(b.status));
      return status == 0 ? b.priority.compareTo(a.priority) : status;
    });
  }
  return result;
}

int _statusOrder(String status) => switch (status) {
      'todo' => 0,
      'in_progress' => 1,
      'done' => 2,
      'canceled' => 3,
      _ => 4,
    };

IconData _statusIcon(String status) => switch (status) {
      'done' => Icons.check_circle_outline,
      'in_progress' => Icons.pending_outlined,
      'canceled' => Icons.cancel_outlined,
      _ => Icons.radio_button_unchecked,
    };

Color _statusColor(BuildContext context, String status) => switch (status) {
      'done' => Colors.green,
      'in_progress' => Colors.blue,
      'canceled' => Colors.grey,
      _ => Theme.of(context).colorScheme.primary,
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
