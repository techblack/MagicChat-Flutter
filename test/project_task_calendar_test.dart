import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/project_task_calendar_view.dart';

void main() {
  testWidgets('月历按日期范围展示任务，未排期任务可展开且点击打开详情', (tester) async {
    final opened = <String>[];
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectTaskCalendarView(
                initialMonth: DateTime(2026, 9),
                tasks: _tasks,
                onOpenTask: (task) => opened.add(task.id)))));
    await tester.pumpAndSettle();

    expect(find.text('2026 年 9 月'), findsOneWidget);
    expect(find.text('跨日任务'), findsNWidgets(3));
    expect(find.text('单日任务'), findsOneWidget);
    expect(find.text('未设置日期'), findsOneWidget);
    expect(find.text('未排期任务'), findsNothing);

    await tester.tap(find.text('未设置日期'));
    await tester.pumpAndSettle();
    expect(find.text('未排期任务'), findsOneWidget);

    await tester.tap(find.text('跨日任务').first);
    expect(opened, ['range']);
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026 年 10 月'), findsOneWidget);
  });

  testWidgets('生成项目任务月历截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectTaskCalendarView(
                initialMonth: DateTime(2026, 9),
                tasks: _tasks,
                onOpenTask: (_) {}))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/project_task_calendar.png'));
  });
}

const _tasks = [
  ProjectTask(
      id: 'range',
      projectId: 'project-1',
      title: '跨日任务',
      status: 'in_progress',
      priority: 3,
      startDate: '2026-09-02',
      dueDate: '2026-09-04'),
  ProjectTask(
      id: 'single',
      projectId: 'project-1',
      title: '单日任务',
      status: 'todo',
      priority: 2,
      dueDate: '2026-09-08'),
  ProjectTask(
      id: 'unscheduled',
      projectId: 'project-1',
      title: '未排期任务',
      status: 'todo',
      priority: 1),
];
