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
}

Widget _app() => MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true),
      home: Scaffold(body: ProjectsPage(repository: _ProjectRepository())),
    );

class _ProjectRepository extends DemoRepository {
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
