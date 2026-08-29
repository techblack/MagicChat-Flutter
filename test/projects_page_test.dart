import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/document_editor_page.dart';
import 'package:magicchat_client/features/projects/projects_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('项目列表区分个人项目且不展示虚假任务数', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('我的项目'), findsOneWidget);
    expect(find.text('个人工作区'), findsOneWidget);
    expect(find.text('客户端迭代'), findsOneWidget);
    expect(find.text('跨端功能复刻'), findsOneWidget);
    expect(find.text('0 个任务'), findsNothing);

    await tester.longPress(find.text('我的项目'));
    await tester.pumpAndSettle();
    expect(find.text('编辑项目'), findsOneWidget);
    expect(find.text('删除项目'), findsNothing);
  });

  testWidgets('项目列表支持关键词过滤且项目详情包含目标和成员入口', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '客户端');
    await tester.pump();
    expect(find.text('客户端迭代'), findsOneWidget);
    expect(find.text('我的项目'), findsNothing);

    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    expect(find.text('目标'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    await tester.tap(find.text('目标'));
    await tester.pumpAndSettle();
    expect(find.text('待完善'), findsOneWidget);
    await tester.tap(find.text('成员'));
    await tester.pumpAndSettle();
    expect(find.text('演示用户'), findsOneWidget);
  });

  testWidgets('普通项目可以打开授权群组并选择可用群组', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('授权群组'));
    await tester.pumpAndSettle();
    expect(find.text('授权群组'), findsOneWidget);
    expect(find.text('团队群聊'), findsOneWidget);
    await tester.tap(find.text('团队群聊'));
    await tester.pumpAndSettle();
    expect(find.text('团队群聊'), findsOneWidget);
  });

  testWidgets('新建项目可以直接关联群聊', (tester) async {
    final repository = _ProjectRepository();
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
            useMaterial3: true),
        home: Scaffold(body: ProjectsPage(repository: repository))));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建项目'));
    await tester.pumpAndSettle();
    expect(find.text('关联群聊（可选）'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '发布计划');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(repository.createdGroupIds, ['team']);
  });

  testWidgets('项目工作区提供五种视图和完整任务状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();

    for (final label in ['列表', '看板', '日历', '甘特', '文档']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('完善项目概览'), findsOneWidget);

    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();
    for (final label in ['待处理', '进行中', '已完成', '已取消']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('目录不会误入编辑器且 Markdown 文档可打开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文档'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('产品资料'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEditorPage), findsNothing);

    await tester.tap(find.text('发布说明'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEditorPage), findsOneWidget);
    expect(find.text('输入 Markdown 或文档内容…'), findsOneWidget);
  });

  testWidgets('文档本机草稿可以切换为 Markdown 预览', (tester) async {
    SharedPreferences.setMockInitialValues({
      'magicchat.document.document-1.draft': '# 发布说明\n\n- 项目契约已经对齐',
    });
    await tester.pumpWidget(MaterialApp(
        home: DocumentEditorPage(
            repository: _ProjectRepository(),
            document: const ProjectDocument(
                id: 'document-1',
                projectId: 'project-1',
                title: '发布说明',
                documentType: 'markdown'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('预览'));
    await tester.pumpAndSettle();

    expect(find.text('发布说明'), findsNWidgets(2));
    expect(find.text('项目契约已经对齐', findRichText: true), findsOneWidget);
  });

  testWidgets('任务详情展示活动流且评论立即回显', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完善项目概览'));
    await tester.pumpAndSettle();

    expect(find.text('任务动态'), findsOneWidget);
    expect(find.text('演示用户 创建了任务'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '**联调完成**');
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();
    expect(find.text('联调完成', findRichText: true), findsOneWidget);
  });

  testWidgets('任务编辑使用项目成员选择器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('客户端迭代'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑任务'));
    await tester.pumpAndSettle();

    expect(find.text('负责人'), findsOneWidget);
    expect(find.text('未分配'), findsOneWidget);
    expect(find.text('负责人用户 ID'), findsNothing);
  });
}

Widget _app() => MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true),
      home: Scaffold(body: ProjectsPage(repository: _ProjectRepository())),
    );

class _ProjectRepository extends DemoRepository {
  final createdGroupIds = <String>[];

  @override
  Future<Project> createProject(String name,
      {String description = '', List<String> groupIds = const []}) async {
    createdGroupIds
      ..clear()
      ..addAll(groupIds);
    return Project(id: 'created-project', name: name, description: description);
  }

  @override
  Future<List<Project>> projects() async => const [
        Project(
            id: 'personal-1',
            name: '我的项目',
            description: '个人工作区',
            isPersonal: true),
        Project(id: 'project-1', name: '客户端迭代', description: '跨端功能复刻'),
      ];

  @override
  Future<List<ProjectTask>> tasks(String projectId) async => const [
        ProjectTask(
            id: 'task-1',
            projectId: 'project-1',
            title: '完善项目概览',
            status: 'todo',
            priority: 3),
        ProjectTask(
            id: 'task-2',
            projectId: 'project-1',
            title: '实现任务看板',
            status: 'in_progress'),
        ProjectTask(
            id: 'task-3',
            projectId: 'project-1',
            title: '验证项目契约',
            status: 'done'),
        ProjectTask(
            id: 'task-4',
            projectId: 'project-1',
            title: '废弃旧方案',
            status: 'canceled'),
      ];

  @override
  Future<List<ProjectDocument>> documents(String projectId) async => const [
        ProjectDocument(
            id: 'folder-1',
            projectId: 'project-1',
            title: '产品资料',
            kind: 'folder'),
        ProjectDocument(
            id: 'document-1',
            projectId: 'project-1',
            title: '发布说明',
            documentType: 'markdown'),
      ];
}
