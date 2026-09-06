import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/collapsible_message_content.dart';
import 'package:magicchat_client/main.dart';

void main() {
  testWidgets('长内容首帧直接使用最终折叠高度且不创建尺寸动画', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: CollapsibleMessageContent(
              key: const ValueKey('stable-long-content'),
              variant: CollapsibleMessageVariant.text,
              contentIdentity: 'stable-long',
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue,
              builder: (_) => const SizedBox(height: 520),
            ),
          ),
        ),
      ),
    ));

    final firstFrameHeight = tester
        .getSize(find.byKey(const ValueKey('stable-long-content')))
        .height;
    expect(firstFrameHeight, lessThan(520));
    expect(find.byType(AnimatedSize), findsNothing);

    await tester.pump();
    expect(find.text('展开'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('stable-long-content')))
            .height,
        firstFrameHeight);
  });

  testWidgets('长内容按平台阈值折叠并可展开收起', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: CollapsibleMessageContent(
              key: const ValueKey('long-content'),
              variant: CollapsibleMessageVariant.text,
              contentIdentity: 'long',
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue,
              builder: (_) => const SizedBox(height: 420),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('展开'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('long-content'))).height,
        lessThan(420));

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('long-content'))).height,
        greaterThan(420));

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('展开'), findsOneWidget);
  });

  testWidgets('大字号折叠正文与展开按钮保留独立间距', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: CollapsibleMessageContent(
                variant: CollapsibleMessageVariant.text,
                contentIdentity: 'large-text',
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                builder: (_) => Text(List.filled(30, '大字号正文').join('\n')),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final content = tester.getRect(
        find.byKey(const ValueKey('collapsible-message-content-clip')));
    final toggle = tester
        .getRect(find.byKey(const ValueKey('collapsible-message-toggle')));
    expect(toggle.top - content.bottom, greaterThanOrEqualTo(6));
  });

  testWidgets('短内容不显示折叠操作', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: CollapsibleMessageContent(
            variant: CollapsibleMessageVariant.markdown,
            contentIdentity: 'short',
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue,
            builder: (_) => const SizedBox(height: 80),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('collapsible-message-toggle')), findsNothing);
  });

  testWidgets('会话中的长文本和 Markdown 均默认折叠', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: _LongMessageRepository(),
          conversationId: 'conversation-1',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('展开'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('collapsible-message-text-long')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('collapsible-message-markdown-long')),
        findsOneWidget);
    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(richText, contains('@Alice'));
    expect(richText, isNot(contains('{(@user/alice)}')));
  });

  testWidgets('复杂长消息页面上翻后不会被后续布局拉回底部', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: _ScrollableLongMessageRepository(),
          conversationId: 'conversation-1',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    await tester.drag(find.byType(ListView).first, const Offset(0, 360));
    await tester.pump();
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    expect(distanceFromBottom, greaterThan(100));

    await tester.pump(const Duration(seconds: 1));
    expect(position.maxScrollExtent - position.pixels, greaterThan(80));
  });
}

class _LongMessageRepository extends DemoRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      [
        ChatMessage(
          id: 'text-long',
          conversationId: conversationId,
          sequence: 1,
          author: 'Alice',
          text:
              List.generate(28, (index) => '第 ${index + 1} 行长文本内容').join('\n'),
        ),
        ChatMessage(
          id: 'markdown-long',
          conversationId: conversationId,
          sequence: 2,
          author: 'Alice',
          contentType: 'markdown',
          text: [
            '# 发布计划 {(@user/alice)}',
            ...List.generate(24, (index) => '- 第 ${index + 1} 项任务'),
          ].join('\n'),
        ),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'alice', name: 'Alice'),
      ];

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '项目群', type: 'group'),
      ];
}

class _ScrollableLongMessageRepository extends _LongMessageRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      List.generate(
        16,
        (index) => ChatMessage(
          id: 'long-$index',
          conversationId: conversationId,
          sequence: index + 1,
          author: 'Alice',
          contentType: index.isEven ? 'markdown' : 'text',
          text: List.generate(24, (line) => '${index + 1}-${line + 1} 复杂消息内容')
              .join('\n'),
        ),
      );
}
