import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contact_category_page.dart';
import 'package:magicchat_client/features/contacts/entity_details_page.dart';
import 'package:magicchat_client/features/projects/document_editor_page.dart';
import 'package:magicchat_client/features/projects/project_task_details_page.dart';
import 'package:magicchat_client/features/projects/project_workspace_page.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('一级导航返回到切换前的页面', (tester) async {
    await _pumpApp(tester, DemoRepository());
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '联系人');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '消息');
  });

  testWidgets('联系人详情进入会话后返回同一联系人详情', (tester) async {
    await _pumpApp(tester, DemoRepository());
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(250, 500), const Offset(0, -220));
    await tester.pumpAndSettle();
    final contact = find.widgetWithText(ListTile, '小助手');
    await tester.tap(contact);
    await tester.pumpAndSettle();
    expect(find.byType(EntityDetailsPage), findsOneWidget);

    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();

    expect(find.byType(EntityDetailsPage), findsOneWidget);
    expect(find.text('小助手'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '联系人');
  });

  testWidgets('联系人分类进入会话后恢复分类和联系人详情', (tester) async {
    await _pumpApp(tester, _NavigationRepository());
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contact-category-allApps')));
    await tester.pumpAndSettle();
    expect(find.byType(ContactCategoryPage), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '智能助手'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();
    expect(find.byType(EntityDetailsPage), findsOneWidget);
    expect(find.text('智能助手'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ContactCategoryPage), findsOneWidget);
    expect(find.text('所有应用'), findsWidgets);
  });

  testWidgets('设置页搜索联系人进入会话后逐层返回联系人和设置页', (tester) async {
    await _pumpApp(tester, _NavigationRepository());
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '设置');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '搜索消息、联系人和项目'), 'Alice');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contact:user:alice')));
    await tester.pumpAndSettle();
    expect(find.byType(EntityDetailsPage), findsOneWidget);

    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();
    expect(find.byType(EntityDetailsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_sectionTitle(tester), '设置');
  });

  testWidgets('设置页搜索项目打开工作区后返回设置页', (tester) async {
    await _pumpApp(tester, _NavigationRepository());
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '搜索消息、联系人和项目'), '导航项目');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project:project-1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectWorkspacePage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '设置');
  });

  testWidgets('设置页搜索聊天记录打开消息后返回设置页', (tester) async {
    await _pumpApp(tester, _NavigationRepository());
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '搜索消息、联系人和项目'), '唯一消息');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message:alice:message-1')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回会话列表'), findsOneWidget);

    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '设置');
  });

  testWidgets('聊天卡片进入任务和文档后均返回原会话', (tester) async {
    await _pumpApp(tester, _CardNavigationRepository());
    await tester.tap(find.text('工程群'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('深链任务'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTaskDetailsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('深链任务'), findsOneWidget);
    expect(find.byTooltip('返回会话列表'), findsOneWidget);

    await tester.tap(find.text('发布说明'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEditorPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('发布说明'), findsOneWidget);
    expect(find.byTooltip('返回会话列表'), findsOneWidget);

    await tester.tap(find.text('缺失任务'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务加载失败'), findsOneWidget);
    expect(find.text('发布说明'), findsOneWidget);
    expect(find.byTooltip('返回会话列表'), findsOneWidget);
  });

  testWidgets('从当前会话打开托盘会话后返回原会话', (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var request = 0;
    String? target;
    late StateSetter setHostState;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      setHostState = setState;
      return AppShell(
          repository: _ConversationNavigationRepository(),
          trayConversationId: target,
          trayOpenRequest: request);
    })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会话 A'));
    await tester.pumpAndSettle();

    setHostState(() {
      target = 'conversation-b';
      request++;
    });
    await tester.pumpAndSettle();
    expect(find.text('会话 B'), findsOneWidget);
    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();
    expect(find.text('会话 A'), findsOneWidget);
  });

  testWidgets('前台点击系统通知进入会话后返回原页面', (tester) async {
    await _pumpApp(tester, _NavigationRepository());
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '设置');

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'magicchat/push',
      const StandardMethodCodec().encodeMethodCall(const MethodCall(
          'routeOpened', {'conversation_id': 'alice', 'message_id': ''})),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回会话列表'), findsOneWidget);
    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();
    expect(_sectionTitle(tester), '设置');
  });
}

Future<void> _pumpApp(
    WidgetTester tester, MagicChatRepository repository) async {
  tester.view.physicalSize = const Size(500, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: AppShell(repository: repository)));
  await tester.pumpAndSettle();
}

String _sectionTitle(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('app-section-title'))).data!;

class _NavigationRepository extends DemoRepository {
  static const alice =
      Contact(id: 'alice', name: 'Alice', email: 'alice@example.com');
  static const assistant =
      Contact(id: 'assistant', name: '智能助手', type: 'app', online: true);

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async =>
      const [alice, assistant];

  @override
  Future<ContactDirectory> contactDirectory({String keyword = ''}) async =>
      const ContactDirectory(
          contacts: [alice, assistant], mode: 'organization');

  @override
  Future<List<Contact>> resolveUsers(List<String> userIds) async =>
      const [alice].where((contact) => userIds.contains(contact.id)).toList();

  @override
  Future<ChatConversation> createDirectConversation(String userId) async =>
      ChatConversation(id: userId, title: 'Alice');

  @override
  Future<ChatConversation> createAppConversation(String appId) async =>
      ChatConversation(id: appId, title: '智能助手', type: 'app');

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'alice', title: 'Alice'),
        ChatConversation(id: 'assistant', title: '智能助手', type: 'app'),
      ];

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-1', name: '导航项目'),
      ];

  @override
  Future<List<MessageSearchResult>> searchMessages(String query,
          {String? conversationId,
          String? senderId,
          DateTime? from,
          DateTime? to}) async =>
      const [
        MessageSearchResult(
          conversationId: 'alice',
          conversationName: 'Alice',
          message: ChatMessage(
              id: 'message-1',
              conversationId: 'alice',
              sequence: 1,
              author: 'Alice',
              text: '唯一消息'),
        ),
      ];
}

class _CardNavigationRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '工程群', type: 'group'),
      ];

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
          id: 'task-card',
          conversationId: 'conversation-1',
          sequence: 1,
          author: 'Alice',
          contentType: 'card',
          text: '[卡片] 深链任务',
          rawBody: {
            'type': 'card',
            'title': '深链任务',
            'description': '项目：发布计划',
            'url': '/projects/project-1?taskId=task-1',
          },
        ),
        ChatMessage(
          id: 'document-card',
          conversationId: 'conversation-1',
          sequence: 2,
          author: 'Alice',
          contentType: 'card',
          text: '[卡片] 发布说明',
          rawBody: {
            'type': 'card',
            'title': '发布说明',
            'description': '项目：发布计划',
            'url': '/documents/markdown/document-1',
          },
        ),
        ChatMessage(
          id: 'missing-task-card',
          conversationId: 'conversation-1',
          sequence: 3,
          author: 'Alice',
          contentType: 'card',
          text: '[卡片] 缺失任务',
          rawBody: {
            'type': 'card',
            'title': '缺失任务',
            'description': '项目：发布计划',
            'url': '/projects/project-1?taskId=missing',
          },
        ),
      ];

  @override
  Future<List<Project>> projects() async => const [
        Project(id: 'project-1', name: '发布计划'),
      ];

  @override
  Future<ProjectTask> task(String projectId, String taskId) async {
    if (taskId == 'missing') throw StateError('任务不存在');
    return ProjectTask(
        id: taskId, projectId: projectId, title: '深链任务', status: 'in_progress');
  }

  @override
  Future<List<ProjectTaskActivity>> taskActivities(
          String projectId, String taskId) async =>
      const [];

  @override
  Future<ProjectDocument> document(String documentId) async =>
      const ProjectDocument(
          id: 'document-1',
          projectId: 'project-1',
          title: '发布说明',
          documentType: 'markdown');
}

class _ConversationNavigationRepository extends DemoRepository {
  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-a', title: '会话 A'),
        ChatConversation(id: 'conversation-b', title: '会话 B'),
      ];

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [];
}
