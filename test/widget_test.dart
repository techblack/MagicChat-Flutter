import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magicchat_client/main.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/auth_service.dart';
import 'package:magicchat_client/data/server_store.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/conversation_details_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HistoryRepository extends DemoRepository {
  final messageRequests = <int?>[];

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'history', title: '历史会话', type: 'group'),
      ];

  @override
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50}) async {
    messageRequests.add(beforeSeq);
    final end = beforeSeq == null ? 30 : beforeSeq - 1;
    final start = end - limit + 1 > 1 ? end - limit + 1 : 1;
    return List.generate(
        end - start + 1,
        (index) => ChatMessage(
            id: 'history-${start + index}',
            conversationId: conversationId,
            sequence: start + index,
            createdAt: DateTime.now()
                .subtract(Duration(minutes: end - (start + index)))
                .toIso8601String(),
            author: '成员',
            text: '历史消息 ${start + index}'));
  }
}

class _SendRepository extends DemoRepository {
  final completer = Completer<void>();
  var sendCount = 0;
  final clientMessageIds = <String>[];

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [];

  @override
  Future<void> sendMessage(String conversationId, String text,
      {String? replyToMessageId, String? clientMessageId}) {
    sendCount++;
    clientMessageIds.add(clientMessageId!);
    return completer.future;
  }
}

class _RetrySendRepository extends DemoRepository {
  final clientMessageIds = <String>[];
  var confirmed = false;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      confirmed
          ? [
              ChatMessage(
                  id: 'confirmed-message',
                  clientMessageId: clientMessageIds.last,
                  conversationId: conversationId,
                  sequence: 1,
                  author: '我',
                  text: '失败后重试',
                  mine: true),
            ]
          : const [];

  @override
  Future<void> sendMessage(String conversationId, String text,
      {String? replyToMessageId, String? clientMessageId}) async {
    clientMessageIds.add(clientMessageId!);
    if (clientMessageIds.length == 1) throw StateError('network');
    confirmed = true;
  }
}

void main() {
  test('构造第三方登录授权地址并编码 provider key', () {
    expect(
        buildThirdPartyLoginUri('https://chat.example.com/base', 'company/sso'),
        Uri.parse(
            'https://chat.example.com/base/api/client/auth/third-party/company%2Fsso/start?redirect=/init'));
  });

  testWidgets('登录表单校验输入并规范化服务器地址', (tester) async {
    final service = AuthService(
        client: MockClient((_) async => http.Response(
            '{"data":{"password_login_enabled":true,"email_code_login_enabled":false,"third_party_providers":[]}}',
            200)));
    String? submittedServer;
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        initialServer: 'chat.example.com/',
        authService: service,
        onLogin: (server, email, password) async => submittedServer = server,
        onCodeLogin: (_, __, ___) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('请输入邮箱'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(submittedServer, isNull);

    await tester.enterText(
        find.widgetWithText(TextFormField, '邮箱'), 'alice@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, '密码'), 'secret');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(submittedServer, 'https://chat.example.com');
  });

  testWidgets('登录页可从服务器管理列表选择地址', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const store = ServerStore();
    await store.add('团队服务器', 'https://team.example.com/base');
    final service = AuthService(
        client: MockClient((_) async => http.Response(
            '{"data":{"password_login_enabled":true,"email_code_login_enabled":false,"third_party_providers":[]}}',
            200)));
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        initialServer: officialServerUrl,
        authService: service,
        serverStore: store,
        onLogin: (_, __, ___) async {},
        onCodeLogin: (_, __, ___) async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('服务器管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('团队服务器'));
    await tester.pumpAndSettle();

    final serverField = find.widgetWithText(TextFormField, '服务器地址');
    expect(tester.widget<TextFormField>(serverField).controller?.text,
        'https://team.example.com/base');
  });

  testWidgets('登录页显示会话过期提示', (tester) async {
    final service = AuthService(
        client: MockClient((_) async => http.Response(
            '{"data":{"password_login_enabled":true,"email_code_login_enabled":false,"third_party_providers":[]}}',
            200)));
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        initialServer: 'https://chat.example.com',
        initialError: '登录已过期，请重新登录',
        authService: service,
        onLogin: (_, __, ___) async {},
        onCodeLogin: (_, __, ___) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
  });

  testWidgets('邮箱验证码登录过滤粘贴分隔符并提交', (tester) async {
    final service = AuthService(
        client: MockClient((request) async => request.url.path.endsWith('/info')
            ? http.Response(
                '{"data":{"password_login_enabled":true,"email_code_login_enabled":true,"third_party_providers":[]}}',
                200)
            : http.Response(
                '{"success":true,"data":{"expires_in_seconds":600,"retry_after_seconds":0}}',
                200)));
    String? submittedCode;
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        initialServer: 'https://chat.example.com',
        authService: service,
        onLogin: (_, __, ___) async {},
        onCodeLogin: (_, __, code) async => submittedCode = code,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, '邮箱'), 'alice@example.com');
    await tester.tap(find.text('使用邮箱验证码登录'));
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    final codeField = find.widgetWithText(TextFormField, '邮箱验证码');
    await tester.enterText(codeField, '1234 5678');
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.text('登录').last);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(
        tester.widget<TextFormField>(codeField).controller?.text, '12345678');
    expect(submittedCode, '12345678');
  });

  testWidgets('显示跨端导航入口', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: DemoRepository())));
    await tester.pump();
    expect(find.text('MagicChat'), findsOneWidget);
    expect(find.text('消息'), findsWidgets);
    expect(find.text('联系人'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
  });

  testWidgets('桌面快捷键 Ctrl-K 可打开综合搜索', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: DemoRepository())));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(400, 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('综合搜索'), findsOneWidget);
  });

  testWidgets('主导航显示未读数和当前模块', (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: DemoRepository())));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(Badge), matching: find.text('2')),
        findsWidgets);
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-section-title')), findsOneWidget);
    expect(find.text('联系人'), findsWidgets);
  });

  testWidgets('移动端聊天详情收起全局导航并可返回', (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: AppShell(repository: DemoRepository())));
    await tester.pumpAndSettle();

    expect(MediaQuery.sizeOf(tester.element(find.byType(AppShell))).width, 500);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'MagicChat');
    await tester.pump();
    expect(find.text('团队群聊'), findsNothing);
    await tester.tap(find.text('MagicChat 小助手'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('返回会话列表'), findsOneWidget);
    expect(find.byTooltip('检索当前会话'), findsOneWidget);
    expect(find.byTooltip('聊天详情'), findsOneWidget);
    final title = find.byKey(const ValueKey('conversation-header-title'));
    final header = find.byKey(const ValueKey('conversation-header-background'));
    final headerSafeArea =
        find.byKey(const ValueKey('conversation-header-safe-area'));
    expect(find.text('MagicChat 小助手'), findsOneWidget);
    expect(
        find.descendant(of: header, matching: headerSafeArea), findsOneWidget);
    expect(
        find.descendant(of: headerSafeArea, matching: title), findsOneWidget);
    expect(tester.getSize(header).width, 500);
    expect(tester.getCenter(title).dx, 250);

    await tester.tap(find.byTooltip('聊天详情'));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationDetailsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('返回会话列表'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('MagicChat 小助手'), findsOneWidget);
    expect(find.text('团队群聊'), findsNothing);
  });

  testWidgets('会话草稿按会话恢复', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget page() => MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: DemoRepository(),
                conversationId: 'conversation-1')));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '稍后发送');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('稍后发送'), findsOneWidget);
  });

  testWidgets('消息立即进入发送中状态并清空输入，空输入不会重复提交', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _SendRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: repository, conversationId: 'conversation-1'))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '只发送一次');
    final send = find.byTooltip('发送');
    await tester.tap(send);
    await tester.pump();

    expect(repository.sendCount, 1);
    expect(find.text('只发送一次'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
    await tester.tap(send);
    expect(repository.sendCount, 1);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('optimistic-message-sending')),
        findsOneWidget);

    await tester.enterText(find.byType(TextField), '发送期间的新草稿');
    repository.completer.complete();
    await tester.pump(const Duration(milliseconds: 50));
    expect(repository.sendCount, 1);
    expect(find.text('发送期间的新草稿'), findsOneWidget);
  });

  testWidgets('乐观消息失败后使用相同客户端消息 ID 重试并由真实消息替换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _RetrySendRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: repository, conversationId: 'conversation-1'))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '失败后重试');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('重新发送消息'), findsOneWidget);
    expect(repository.clientMessageIds, hasLength(1));
    await tester.tap(find.byTooltip('重新发送消息'));
    await tester.pumpAndSettle();

    expect(repository.clientMessageIds, hasLength(2));
    expect(repository.clientMessageIds[1], repository.clientMessageIds[0]);
    expect(find.byTooltip('重新发送消息'), findsNothing);
    expect(find.text('失败后重试'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('optimistic-message-sending')), findsNothing);
  });

  testWidgets('宽屏聊天顶栏背景横跨完整消息区域', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessagesPage(
          repository: DemoRepository(),
          selectedId: 'welcome',
          onSelect: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final topBar = find.byKey(const ValueKey('conversation-wide-top-bar'));
    expect(topBar, findsOneWidget);
    expect(tester.getSize(topBar).width, 1000);
    final header = find.byKey(const ValueKey('conversation-header-background'));
    expect(header, findsOneWidget);
    expect(tester.getSize(header).width, 1000);
  });

  testWidgets('未选会话时显示明确的选择引导', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessagesPage(
          repository: DemoRepository(),
          selectedId: null,
          onSelect: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('conversation-selection-state')),
        findsOneWidget);
    expect(find.text('选择一个会话'), findsOneWidget);
    expect(find.text('暂无消息'), findsNothing);
  });

  testWidgets('阅读历史时提示新消息并可回到最新', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RealtimeStore();
    store.conversations['history'] =
        const ChatConversation(id: 'history', title: '历史会话', type: 'group');
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: _HistoryRepository(),
                realtimeStore: store,
                conversationId: 'history'))));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 420));
    await tester.pumpAndSettle();
    store.apply({
      'cursor': 1,
      'event': 'message.created',
      'payload': {
        'id': 'incoming-1',
        'conversation_id': 'history',
        'seq': 31,
        'sender': {'id': 'user-1', 'name': 'Alice'},
        'body': {'type': 'text', 'content': '新到消息'},
      },
    });
    await tester.pump();

    expect(find.text('新消息 1'), findsOneWidget);
    await tester.tap(find.text('新消息 1'));
    await tester.pumpAndSettle();
    expect(find.text('新消息 1'), findsNothing);
  });

  testWidgets('搜索历史消息按目标序号加载并可返回最新', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _HistoryRepository();
    var returnedToLatest = false;
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: repository,
                conversationId: 'history',
                focusMessageId: 'history-10',
                focusMessageSequence: 10,
                onMessageFocused: () => returnedToLatest = true))));
    await tester.pumpAndSettle();

    expect(repository.messageRequests, [36]);
    expect(find.text('历史消息 10'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('message-time-history-10')), findsOneWidget);
    expect(find.text('返回最新消息'), findsOneWidget);

    await tester.tap(find.text('返回最新消息'));
    await tester.pumpAndSettle();
    expect(repository.messageRequests, [36, null]);
    expect(returnedToLatest, isTrue);
    expect(find.text('返回最新消息'), findsNothing);
  });
}
