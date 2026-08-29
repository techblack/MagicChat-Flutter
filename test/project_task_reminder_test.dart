import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/project_task_details_page.dart';

void main() {
  testWidgets('任务详情展示周期提醒和星期', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ProjectTaskDetailsPage(
            repository: _ReminderRepository(),
            project: const Project(id: 'project-1', name: '发布计划'),
            task: _weeklyTask)));
    await tester.pumpAndSettle();

    expect(find.text('每周一、三、五 09:30'), findsOneWidget);
  });

  testWidgets('已完成任务的提醒显示为已暂停', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ProjectTaskDetailsPage(
            repository: _ReminderRepository(),
            project: const Project(id: 'project-1', name: '发布计划'),
            task: const ProjectTask(
                id: 'task-2',
                projectId: 'project-1',
                title: '发布检查',
                status: 'done',
                reminder: {
                  'mode': 'once',
                  'at': '2026-09-01T09:30:00+08:00',
                  'timezone': 'Asia/Shanghai',
                }))));
    await tester.pumpAndSettle();

    expect(find.textContaining('已暂停 · 一次性提醒'), findsOneWidget);
  });

  testWidgets('生成任务提醒详情截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: ProjectTaskDetailsPage(
            repository: _ReminderRepository(),
            project: const Project(id: 'project-1', name: '发布计划'),
            task: _weeklyTask)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/project_task_reminder.png'));
  });
}

const _weeklyTask = ProjectTask(
    id: 'task-1',
    projectId: 'project-1',
    title: '发布检查',
    status: 'in_progress',
    priority: 3,
    description: '核对发布清单并记录结果。',
    dueDate: '2026-09-04',
    reminder: {
      'mode': 'recurring',
      'frequency': 'weekly',
      'time': '09:30',
      'weekdays': [1, 3, 5],
      'timezone': 'Asia/Shanghai',
      'state': 'scheduled',
    });

class _ReminderRepository extends DemoRepository {
  @override
  Future<List<ProjectTaskActivity>> taskActivities(
          String projectId, String taskId) async =>
      const [];
}
