import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/project_workspace_page.dart';
import 'package:magicchat_client/features/projects/project_task_details_page.dart';
import 'package:magicchat_client/features/projects/projects_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('项目工作区使用全屏页面并可返回项目列表', (tester) async {
    await tester.pumpWidget(_app(_WorkspaceRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectWorkspacePage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('原始任务'), findsOneWidget);

    await tester.tap(find.text('原始任务'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTaskDetailsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProjectWorkspacePage), findsOneWidget);
    expect(find.text('原始任务'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProjectWorkspacePage), findsNothing);
    expect(find.text('客户端迭代'), findsOneWidget);
  });

  testWidgets('任务 CRUD 和状态更新后保留工作区并原位刷新', (tester) async {
    final repository = _WorkspaceRepository();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('推进任务状态'));
    await tester.pumpAndSettle();
    expect(repository.taskItems.single.status, 'in_progress');
    expect(find.byType(ProjectWorkspacePage), findsOneWidget);
    expect(find.textContaining('进行中'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑任务'));
    await tester.pumpAndSettle();
    final title = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == '标题');
    await tester.enterText(title, '已编辑任务');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectWorkspacePage), findsOneWidget);
    expect(find.text('已编辑任务'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repository.taskItems, isEmpty);
    expect(find.byType(ProjectWorkspacePage), findsOneWidget);
    expect(find.text('暂无匹配任务'), findsOneWidget);

    await tester.tap(find.byTooltip('新建任务'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == '任务标题'),
        '新建任务');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(repository.taskItems.single.title, '新建任务');
    expect(find.byType(ProjectWorkspacePage), findsOneWidget);
    expect(find.text('新建任务'), findsOneWidget);
  });

  testWidgets('移动端键盘弹出时新建任务表单和提交按钮仍可达', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(_app(_WorkspaceRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建任务'));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, '创建');
    final dueDate = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.labelText == '截止日期（YYYY-MM-DD）');
    await tester.ensureVisible(dueDate);
    await tester.pumpAndSettle();

    expect(submit, findsOneWidget);
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(360));
  });

  testWidgets('项目视图选择在返回并重新打开后保持', (tester) async {
    await tester.pumpWidget(_app(_WorkspaceRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('甘特'));
    await tester.pumpAndSettle();

    var controller =
        DefaultTabController.of(tester.element(find.byType(TabBar)));
    expect(controller.index, 3);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();

    controller = DefaultTabController.of(tester.element(find.byType(TabBar)));
    expect(controller.index, 3);
  });
}

Widget _app(MagicChatRepository repository) => MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3a76f0)),
          useMaterial3: true),
      home: Scaffold(body: ProjectsPage(repository: repository)),
    );

class _WorkspaceRepository extends DemoRepository {
  final taskItems = <ProjectTask>[
    const ProjectTask(
        id: 'task-1', projectId: 'project-1', title: '原始任务', status: 'todo'),
  ];

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-1', name: '客户端迭代'),
      ];

  @override
  Future<ProjectTaskPage> projectTaskPage(String projectId,
          {String? cursor,
          int limit = 100,
          String keyword = '',
          String label = '',
          List<String> statuses = const [],
          List<int> priorities = const []}) async =>
      ProjectTaskPage(tasks: List.of(taskItems));

  @override
  Future<List<ProjectMember>> projectMembers(String projectId) async =>
      const [];

  @override
  Future<ProjectTask> createTask(String projectId, String title,
      {String description = '',
      String status = 'todo',
      int priority = 2,
      String? startDate,
      String? dueDate,
      List<String> labels = const [],
      String? assigneeUserId,
      Map<String, dynamic>? reminder}) async {
    final task = ProjectTask(
        id: 'task-created',
        projectId: projectId,
        title: title,
        description: description,
        status: status,
        priority: priority,
        startDate: startDate,
        dueDate: dueDate,
        labels: labels,
        reminder: reminder);
    taskItems.add(task);
    return task;
  }

  @override
  Future<ProjectTask> updateTaskStatus(
      String projectId, String taskId, String status) async {
    final current = taskItems.singleWhere((task) => task.id == taskId);
    final updated = _copy(current, status: status);
    taskItems[taskItems.indexOf(current)] = updated;
    return updated;
  }

  @override
  Future<ProjectTask> updateTask(
      String projectId, String taskId, ProjectTaskUpdate update) async {
    final current = taskItems.singleWhere((task) => task.id == taskId);
    final updated = ProjectTask(
        id: current.id,
        projectId: current.projectId,
        title: update.title,
        description: update.description,
        status: update.status,
        priority: update.priority,
        startDate: update.startDate,
        dueDate: update.dueDate,
        labels: update.labels,
        reminder: update.reminder);
    taskItems[taskItems.indexOf(current)] = updated;
    return updated;
  }

  @override
  Future<void> deleteTask(String projectId, String taskId) async {
    taskItems.removeWhere((task) => task.id == taskId);
  }

  ProjectTask _copy(ProjectTask task, {required String status}) => ProjectTask(
      id: task.id,
      projectId: task.projectId,
      title: task.title,
      description: task.description,
      status: status,
      priority: task.priority,
      startDate: task.startDate,
      dueDate: task.dueDate,
      labels: task.labels,
      reminder: task.reminder);
}
