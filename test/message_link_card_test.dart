import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/message_link_card.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('链接卡片展示标题和地址并回调规范化 URI', (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageLinkCard(
          title: 'Example Docs',
          description: 'https://example.com/docs',
          url: '  HTTPS://example.com/docs  ',
          onOpen: (uri) => opened = uri,
        ),
      ),
    ));

    expect(find.text('Example Docs'), findsOneWidget);
    expect(find.text('https://example.com/docs'), findsOneWidget);
    await tester.tap(find.text('Example Docs'));
    expect(opened?.scheme, 'https');
    expect(opened?.host, 'example.com');
  });

  testWidgets('不安全地址仍展示卡片但不启用点击', (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageLinkCard(
          title: '不可信链接',
          description: 'javascript:alert(1)',
          url: 'javascript:alert(1)',
          onOpen: (uri) => opened = uri,
        ),
      ),
    ));

    expect(find.text('不可信链接'), findsOneWidget);
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNull);
    await tester.tap(find.text('不可信链接'));
    expect(opened, isNull);
  });

  testWidgets('卡片内部绝对路径通过配置回调打开', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageLinkCard(
          title: '任务动态',
          description: '状态：待办',
          url: ' /projects/project-1?taskId=task-1 ',
          allowInternalPath: true,
          onOpenInternal: (path) => opened = path,
        ),
      ),
    ));

    await tester.tap(find.text('任务动态'));
    expect(opened, '/projects/project-1?taskId=task-1');
  });

  testWidgets('链接消息不会把内部路径当作可点击外链', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageLinkCard(
          title: '项目地址',
          description: '/projects/project-1',
          url: '/projects/project-1',
          onOpenInternal: (path) => opened = path,
        ),
      ),
    ));

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNull);
    expect(opened, isNull);
  });

  testWidgets('ConversationView 使用结构化卡片并转发内部路径回调', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: _StructuredMessageRepository(),
          conversationId: 'welcome',
          onOpenInternalLink: (path) => opened = path,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Example Docs'), findsOneWidget);
    expect(find.text('任务动态'), findsOneWidget);
    await tester.tap(find.text('任务动态'));
    expect(opened, '/projects/project-1?taskId=task-1');
  });

  testWidgets('链接卡片截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('结构化消息')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MessageLinkCard(
                title: 'Example Docs',
                description: 'https://example.com/docs',
                url: 'https://example.com/docs',
              ),
              SizedBox(height: 12),
              MessageLinkCard(
                title: '任务动态',
                description: '状态：待办\n负责人：张三',
                url: '/projects/one?taskId=task-1',
                icon: Icons.open_in_new,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('evidence/message_link_card.png'),
    );
  });
}

class _StructuredMessageRepository extends DemoRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
          id: 'link-1',
          author: 'Alice',
          contentType: 'link',
          rawBody: {
            'type': 'link',
            'title': 'Example Docs',
            'url': 'https://example.com/docs',
          },
          text: '[链接] Example Docs',
        ),
        ChatMessage(
          id: 'card-1',
          author: 'Alice',
          contentType: 'card',
          rawBody: {
            'type': 'card',
            'title': '任务动态',
            'description': '状态：待办',
            'url': '/projects/project-1?taskId=task-1',
          },
          text: '[卡片] 任务动态',
        ),
      ];
}
