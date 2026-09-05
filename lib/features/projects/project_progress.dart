import '../../domain/models.dart';

/// 项目任务的轻量进度摘要，用于目标概览和桌面/移动端一致的统计口径。
class ProjectProgressSummary {
  const ProjectProgressSummary({
    required this.total,
    required this.completed,
    required this.active,
    required this.pending,
    required this.canceled,
    required this.overdue,
  });

  final int total;
  final int completed;
  final int active;
  final int pending;
  final int canceled;
  final int overdue;

  double get completionRatio => total == 0 ? 0 : completed / total;
}

ProjectProgressSummary summarizeProjectTasks(Iterable<ProjectTask> tasks,
    {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  var completed = 0;
  var active = 0;
  var pending = 0;
  var canceled = 0;
  var overdue = 0;
  var total = 0;

  for (final task in tasks) {
    total++;
    switch (task.status) {
      case 'done':
        completed++;
      case 'in_progress':
        active++;
      case 'canceled':
        canceled++;
      default:
        pending++;
    }
    if (task.status == 'done' || task.status == 'canceled') continue;
    final due = DateTime.tryParse(task.dueDate ?? '')?.toLocal();
    if (due != null && due.isBefore(today)) overdue++;
  }

  return ProjectProgressSummary(
      total: total,
      completed: completed,
      active: active,
      pending: pending,
      canceled: canceled,
      overdue: overdue);
}
