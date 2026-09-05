import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/collapsible_message_content.dart';
import 'package:magicchat_client/main.dart';

void main() {
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
