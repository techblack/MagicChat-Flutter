import 'package:flutter/material.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/projects_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString('magicchat.document.document-3.draft', '''
# 九月版本发布说明

- 项目工作区契约已对齐
- 任务四种状态已经覆盖
- 文档目录树支持展开与移动

> 正文协作同步将在下一阶段接入。
''');
  runApp(const _ProjectWorkspaceHarness());
}

class _ProjectWorkspaceHarness extends StatelessWidget {
  const _ProjectWorkspaceHarness();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
            useMaterial3: true),
        home: Scaffold(
          appBar: AppBar(title: const Text('MagicChat 项目工作区')),
          body: ProjectsPage(repository: _ProjectHarnessRepository()),
        ),
      );
}

class _ProjectHarnessRepository extends DemoRepository {
  @override
  Future<List<Project>> projects() async => const [
        Project(
            id: 'personal-1',
            name: '我的项目',
            description: '个人待办与灵感记录',
            isPersonal: true),
        Project(
            id: 'project-1', name: 'Flutter 客户端迭代', description: '三端功能复刻与体验优化'),
        Project(id: 'project-2', name: '九月发布计划', description: '发布检查、文档与回归验证'),
      ];

  @override
  Future<List<ProjectTask>> tasks(String projectId) async => const [
        ProjectTask(
            id: 'task-1',
            projectId: 'project-1',
            title: '完善项目概览',
            status: 'todo',
            priority: 3,
            description: '对齐个人项目、团队项目和任务统计的服务端契约。',
            dueDate: '2026-09-02',
            labels: ['Flutter', '契约'],
            assignee:
                ProjectUser(id: 'user-alice', name: 'Alice', nickname: '艾丽丝')),
        ProjectTask(
            id: 'task-2',
            projectId: 'project-1',
            title: '接入成员选择器',
            status: 'todo',
            priority: 2),
        ProjectTask(
            id: 'task-3',
            projectId: 'project-1',
            title: '实现任务看板',
            status: 'in_progress',
            priority: 3,
            startDate: '2026-08-28',
            dueDate: '2026-09-04'),
        ProjectTask(
            id: 'task-4',
            projectId: 'project-1',
            title: '整理文档目录',
            status: 'in_progress',
            priority: 1),
        ProjectTask(
            id: 'task-5',
            projectId: 'project-1',
            title: '修正 API 响应解析',
            status: 'done',
            priority: 3),
        ProjectTask(
            id: 'task-6',
            projectId: 'project-1',
            title: '补充定向测试',
            status: 'done',
            priority: 2),
        ProjectTask(
            id: 'task-7',
            projectId: 'project-1',
            title: '沿用旧版任务弹窗',
            status: 'canceled',
            priority: 1),
      ];

  @override
  Future<List<ProjectMember>> projectMembers(String projectId) async => const [
        ProjectMember(
            id: 'demo',
            name: '演示用户',
            email: 'demo@example.com',
            displayNameOverride: '演示用户',
            role: 'owner'),
        ProjectMember(
            id: 'user-alice',
            name: 'Alice',
            nickname: '艾丽丝',
            email: 'alice@example.com',
            displayNameOverride: '艾丽丝'),
        ProjectMember(
            id: 'user-bob',
            name: 'Bob',
            email: 'bob@example.com',
            displayNameOverride: 'Bob'),
      ];

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
          String projectId, String taskId) async =>
      [
        ProjectTaskActivity(
            id: 'activity-1',
            projectId: projectId,
            taskId: taskId,
            type: 'created',
            actor: const ProjectUser(id: 'demo', name: '演示用户'),
            createdAt: '2026-08-28T09:30:00+08:00'),
        ProjectTaskActivity(
            id: 'activity-2',
            projectId: projectId,
            taskId: taskId,
            type: 'updated',
            actor: const ProjectUser(
                id: 'user-alice', name: 'Alice', nickname: '艾丽丝'),
            changes: const [
              ProjectTaskActivityChange(
                  field: 'assignee', from: null, to: 'user-alice'),
              ProjectTaskActivityChange(
                  field: 'due_date', from: null, to: '2026-09-02'),
            ],
            createdAt: '2026-08-28T10:15:00+08:00'),
        ProjectTaskActivity(
            id: 'activity-3',
            projectId: projectId,
            taskId: taskId,
            type: 'commented',
            actor: const ProjectUser(id: 'user-bob', name: 'Bob'),
            content: '**接口字段已核对**，可以进入流程验证。',
            createdAt: '2026-08-29T14:20:00+08:00'),
      ];

  @override
  Future<List<ProjectDocument>> documents(String projectId) async => const [
        ProjectDocument(
            id: 'folder-1',
            projectId: 'project-1',
            title: '产品资料',
            kind: 'folder',
            sortOrder: 0),
        ProjectDocument(
            id: 'document-1',
            projectId: 'project-1',
            title: '需求说明',
            parentId: 'folder-1',
            documentType: 'document',
            sortOrder: 0),
        ProjectDocument(
            id: 'document-2',
            projectId: 'project-1',
            title: '交互验收清单',
            parentId: 'folder-1',
            documentType: 'markdown',
            sortOrder: 1),
        ProjectDocument(
            id: 'document-3',
            projectId: 'project-1',
            title: '发布说明',
            documentType: 'markdown',
            sortOrder: 1),
      ];
}
