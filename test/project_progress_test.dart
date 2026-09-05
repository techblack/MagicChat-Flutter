import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/project_progress.dart';

void main() {
  test('项目目标概览按任务状态和截止日期统计', () {
    final summary = summarizeProjectTasks([
      const ProjectTask(
          id: 'todo', projectId: 'p', title: '待处理', status: 'todo'),
      const ProjectTask(
          id: 'active', projectId: 'p', title: '进行中', status: 'in_progress'),
      const ProjectTask(
          id: 'done', projectId: 'p', title: '已完成', status: 'done'),
      const ProjectTask(
          id: 'cancel', projectId: 'p', title: '已取消', status: 'canceled'),
      const ProjectTask(
          id: 'overdue',
          projectId: 'p',
          title: '逾期',
          status: 'todo',
          dueDate: '2026-09-04'),
    ], now: DateTime(2026, 9, 5, 12));

    expect(summary.total, 5);
    expect(summary.pending, 2);
    expect(summary.active, 1);
    expect(summary.completed, 1);
    expect(summary.canceled, 1);
    expect(summary.overdue, 1);
    expect(summary.completionRatio, .2);
  });

  test('空项目目标概览不会产生 NaN 进度', () {
    final summary = summarizeProjectTasks(const []);
    expect(summary.total, 0);
    expect(summary.completionRatio, 0);
    expect(summary.overdue, 0);
  });
}
