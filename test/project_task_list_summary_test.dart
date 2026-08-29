import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/projects_page.dart';

void main() {
  testWidgets('任务列表摘要展示负责人、排期和标签', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProjectsPage(repository: _TaskListRepository()))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('发布计划'));
    await tester.pumpAndSettle();

    expect(find.textContaining('负责人：艾丽丝'), findsOneWidget);
    expect(find.textContaining('排期：2026-09-01 → 2026-09-04'), findsOneWidget);
    expect(find.textContaining('标签：发布、验收'), findsOneWidget);
  });

  testWidgets('生成任务列表摘要截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProjectsPage(repository: _TaskListRepository()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布计划'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/project_task_list_summary.png'));
  });
}

class _TaskListRepository extends DemoRepository {
  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-1', name: '发布计划', description: '版本发布工作项'),
      ];

  @override
  Future<List<ProjectTask>> tasks(String projectId) async => const [
        ProjectTask(
            id: 'task-1',
            projectId: 'project-1',
            title: '完成发布检查',
            status: 'in_progress',
            priority: 3,
            startDate: '2026-09-01',
            dueDate: '2026-09-04',
            labels: ['发布', '验收'],
            assignee:
                ProjectUser(id: 'user-alice', name: 'Alice', nickname: '艾丽丝')),
      ];

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
          String projectId, String taskId) async =>
      const [];
}
