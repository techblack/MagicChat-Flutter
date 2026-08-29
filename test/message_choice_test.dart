import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('解析选择状态并兼容旧服务端的 null 未答列表', () {
    final state = parseMessageChoiceState({
      'my_option_ids': ['b'],
      'response_count': 3,
      'options': [
        {'id': 'a', 'response_count': 1},
        {'id': 'b', 'response_count': 2},
      ],
    });
    expect(state?.myOptionIds, ['b']);
    expect(state?.selected('b'), isTrue);
    expect(state?.options.map((option) => option.responseCount), [1, 2]);
    expect(
      parseMessageChoiceState({
        'my_option_ids': null,
        'response_count': 0,
        'options': [
          {'id': 'a', 'response_count': 0},
        ],
      })?.myOptionIds,
      isEmpty,
    );
    expect(
      parseMessageChoiceState({
        'my_option_ids': [4],
        'response_count': 0,
        'options': [],
      }),
      isNull,
    );
  });

  testWidgets('多选消息支持勾选多个选项后一次提交', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _ChoiceRepository();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: repository, conversationId: 'welcome'))));
    await tester.pumpAndSettle();

    expect(find.text('请选择项目'), findsOneWidget);
    await tester.tap(find.text('选项 A'));
    await tester.tap(find.text('选项 B'));
    await tester.tap(find.text('提交选择'));
    await tester.pumpAndSettle();

    expect(repository.submittedOptionIds, ['a', 'b']);
    expect(find.text('已提交'), findsOneWidget);
  });

  testWidgets('历史选择状态回显已选项和响应人数', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: _AnsweredChoiceRepository(),
                conversationId: 'welcome'))));
    await tester.pumpAndSettle();

    final selected =
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, '选项 B · 3'));
    expect(selected.selected, isTrue);
    expect(find.text('3 人已选择'), findsOneWidget);
    expect(find.text('提交选择'), findsNothing);
  });

  testWidgets('生成选择消息截图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: _ChoiceRepository(), conversationId: 'welcome'))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('evidence/message_choice.png'));
  });
}

class _ChoiceRepository extends DemoRepository {
  List<String> submittedOptionIds = const [];

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'choice-1',
            conversationId: 'welcome',
            author: '演示用户',
            text: '请选择项目',
            contentType: 'choice',
            rawBody: {
              'type': 'choice',
              'content_type': 'text',
              'content': '请选择项目',
              'selection': 'multiple',
              'options': [
                {'id': 'a', 'label': '选项 A'},
                {'id': 'b', 'label': '选项 B'},
                {'id': 'c', 'label': '选项 C'},
              ],
            }),
      ];

  @override
  Future<void> submitChoice(
      String conversationId, String messageId, List<String> optionIds) async {
    submittedOptionIds = [...optionIds];
  }
}

class _AnsweredChoiceRepository extends _ChoiceRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'choice-answered',
            conversationId: 'welcome',
            author: '演示用户',
            text: '请选择项目',
            contentType: 'choice',
            rawBody: {
              'type': 'choice',
              'content_type': 'text',
              'content': '请选择项目',
              'selection': 'multiple',
              'options': [
                {'id': 'a', 'label': '选项 A'},
                {'id': 'b', 'label': '选项 B'},
              ],
            },
            choice: MessageChoiceState(
                myOptionIds: ['b'],
                responseCount: 3,
                options: [
                  MessageChoiceOption(id: 'a', responseCount: 1),
                  MessageChoiceOption(id: 'b', responseCount: 3),
                ])),
      ];
}
