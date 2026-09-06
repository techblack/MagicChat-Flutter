import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/project_task_details_page.dart';
import 'package:magicchat_client/features/projects/project_task_editor_dialog.dart';

void main() {
  testWidgets('任务详情可编辑全部字段并原位刷新动态', (tester) async {
    final repository = _EditingRepository();
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_detailsApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTaskEditorDialog), findsOneWidget);

    await _enter(tester, '标题', '更新后的任务');
    await _enter(tester, '描述', '**新的说明**');
    await _select<String>(tester, '状态', '进行中');
    await _select<int>(tester, '优先级', '高');
    await _enter(tester, '开始日期（YYYY-MM-DD）', '2026-09-08');
    await _enter(tester, '截止日期（YYYY-MM-DD）', '2026-09-10');
    await _enter(tester, '标签（逗号分隔）', '发布, 客户端, 发布');
    await _select<String>(tester, '负责人', 'Bob · bob@example.com');
    await _select<String>(tester, '提醒模式', '周期性');
    await _select<String>(tester, '重复频率', '每月');
    await _enter(tester, '提醒时间（HH:mm）', '10:30');
    await _enter(tester, '每月日期（1-31）', '15');
    await _enter(tester, '时区', 'Asia/Shanghai');

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final update = repository.lastUpdate!;
    expect(update.title, '更新后的任务');
    expect(update.description, '**新的说明**');
    expect(update.status, 'in_progress');
    expect(update.priority, 3);
    expect(update.assigneeUserId, 'bob');
    expect(update.startDate, '2026-09-08');
    expect(update.dueDate, '2026-09-10');
    expect(update.labels, ['发布', '客户端']);
    expect(update.reminder, {
      'mode': 'recurring',
      'frequency': 'monthly',
      'time': '10:30',
      'timezone': 'Asia/Shanghai',
      'day_of_month': 15,
    });
    expect(find.text('更新后的任务'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('高优先级'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('每月 15 日 10:30'), findsOneWidget);
    expect(find.text('Alice 修改了标题、状态'), findsOneWidget);
    expect(repository.activityRequests, 2);
  });

  testWidgets('保存失败保留编辑内容并可原位重试', (tester) async {
    final repository = _EditingRepository(updateFailures: 1);
    await tester.pumpWidget(_detailsApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();

    await _enter(tester, '标题', '失败后重试');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectTaskEditorDialog), findsOneWidget);
    expect(find.textContaining('保存任务失败'), findsOneWidget);
    expect(_textField(tester, '标题').controller?.text, '失败后重试');

    await tester.tap(find.widgetWithText(FilledButton, '重试保存'));
    await tester.pumpAndSettle();
    expect(repository.updateRequests, 2);
    expect(find.byType(ProjectTaskEditorDialog), findsNothing);
    expect(find.text('失败后重试'), findsOneWidget);
  });

  testWidgets('编辑其他字段时保留完整的每周提醒', (tester) async {
    final repository = _EditingRepository();
    await tester.pumpWidget(MaterialApp(
      home: ProjectTaskDetailsPage(
        repository: repository,
        project: _project,
        task: const ProjectTask(
          id: 'task-1',
          projectId: 'project-1',
          title: '每周任务',
          status: 'todo',
          reminder: {
            'mode': 'recurring',
            'frequency': 'weekly',
            'time': '09:30',
            'weekdays': [1, 3, 5],
            'timezone': 'Asia/Shanghai',
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();
    await _enter(tester, '标题', '更新标题');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(repository.lastUpdate?.reminder, {
      'mode': 'recurring',
      'frequency': 'weekly',
      'time': '09:30',
      'timezone': 'Asia/Shanghai',
      'weekdays': [1, 3, 5],
    });
  });

  testWidgets('标题和标签按 Unicode 字符而非 UTF-16 长度校验', (tester) async {
    final repository = _EditingRepository();
    await tester.pumpWidget(_detailsApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();

    final title = List.filled(240, '😀').join();
    final label = List.filled(32, '🚀').join();
    await _enter(tester, '标题', title);
    await _enter(tester, '标签（逗号分隔）', label);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(repository.lastUpdate?.title, title);
    expect(repository.lastUpdate?.labels, [label]);
    expect(find.textContaining('标题长度必须'), findsNothing);
    expect(find.textContaining('单个标签不能超过'), findsNothing);
  });

  testWidgets('离开未保存的任务编辑器需要二次确认', (tester) async {
    final repository = _EditingRepository();
    await tester.pumpWidget(_detailsApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();
    await _enter(tester, '标题', '尚未保存');

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTaskEditorDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTaskEditorDialog), findsNothing);
    expect(find.text('原始任务'), findsOneWidget);
    expect(repository.updateRequests, 0);
  });

  testWidgets('删除失败保留确认框，重试成功后原路返回', (tester) async {
    final repository = _EditingRepository(deleteFailures: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectTaskDetailsPage(
                        repository: repository,
                        project: _project,
                        task: _task,
                      ),
                    ),
                  ),
                  child: const Text('打开来源页面'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开来源页面'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除任务'));
    await tester.pumpAndSettle();

    expect(find.textContaining('此操作无法撤销'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除任务失败'), findsOneWidget);
    expect(find.text('原始任务'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重试删除'));
    await tester.pumpAndSettle();
    expect(repository.deleteRequests, 2);
    expect(find.byType(ProjectTaskDetailsPage), findsNothing);
    expect(find.text('打开来源页面'), findsOneWidget);
  });
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final finder = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _select<T>(
  WidgetTester tester,
  String label,
  String option,
) async {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<T> &&
        widget.decoration.labelText == label,
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

TextField _textField(WidgetTester tester, String label) =>
    tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    );

Widget _detailsApp(MagicChatRepository repository) => MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3a76f0)),
        useMaterial3: true,
      ),
      home: ProjectTaskDetailsPage(
        repository: repository,
        project: _project,
        task: _task,
      ),
    );

const _project = Project(id: 'project-1', name: '发布计划');
const _task = ProjectTask(
  id: 'task-1',
  projectId: 'project-1',
  title: '原始任务',
  description: '原始说明',
  status: 'todo',
  priority: 2,
);

class _EditingRepository extends DemoRepository {
  _EditingRepository({this.updateFailures = 0, this.deleteFailures = 0});

  int updateFailures;
  int deleteFailures;
  int updateRequests = 0;
  int deleteRequests = 0;
  int activityRequests = 0;
  ProjectTaskUpdate? lastUpdate;

  @override
  Future<List<ProjectMember>> projectMembers(String projectId) async => const [
        ProjectMember(
          id: 'bob',
          name: 'Bob',
          email: 'bob@example.com',
          status: 'active',
        ),
      ];

  @override
  Future<ProjectTask> updateTask(
    String projectId,
    String taskId,
    ProjectTaskUpdate update,
  ) async {
    updateRequests++;
    if (updateFailures > 0) {
      updateFailures--;
      throw StateError('temporary failure');
    }
    lastUpdate = update;
    return ProjectTask(
      id: taskId,
      projectId: projectId,
      title: update.title,
      description: update.description,
      status: update.status,
      priority: update.priority,
      startDate: update.startDate,
      dueDate: update.dueDate,
      labels: update.labels,
      assignee: update.assigneeUserId == 'bob'
          ? const ProjectUser(id: 'bob', name: 'Bob')
          : null,
      reminder: update.reminder,
    );
  }

  @override
  Future<void> deleteTask(String projectId, String taskId) async {
    deleteRequests++;
    if (deleteFailures > 0) {
      deleteFailures--;
      throw StateError('temporary failure');
    }
  }

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
    String projectId,
    String taskId,
  ) async {
    activityRequests++;
    if (activityRequests == 1) return const [];
    return const [
      ProjectTaskActivity(
        id: 'activity-1',
        projectId: 'project-1',
        taskId: 'task-1',
        type: 'updated',
        actor: ProjectUser(id: 'alice', name: 'Alice'),
        createdAt: '2026-09-07T10:00:00Z',
        changes: [
          ProjectTaskActivityChange(field: 'title', from: '原始任务', to: '更新后的任务'),
          ProjectTaskActivityChange(
            field: 'status',
            from: 'todo',
            to: 'in_progress',
          ),
        ],
      ),
    ];
  }
}
