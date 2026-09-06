import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/features/messages/expression_picker.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('官方表情清单包含 64 个具名项目和 8 个默认常用', () {
    expect(allExpressionItems, hasLength(64));
    expect(allExpressionItems.map((item) => item.value).toSet(), hasLength(64));
    expect(
      allExpressionItems.firstWhere((item) => item.value == '🤝').label,
      '握手',
    );
    expect(
      frequentExpressionItems(const []).map((item) => item.value),
      defaultFrequentExpressionValues,
    );
  });

  test('常用表情按次数和最近时间排序并淘汰 30 天前记录', () {
    final now = DateTime.utc(2026, 9, 7, 12);
    final normalized = normalizeExpressionUsage([
      {
        'value': '😂',
        'count': 2,
        'last_used_at':
            now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      },
      {
        'value': '🤝',
        'count': 2,
        'last_used_at':
            now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      },
      {
        'value': '👌',
        'count': 3,
        'last_used_at':
            now.subtract(const Duration(days: 31)).millisecondsSinceEpoch,
      },
    ], now);

    expect(normalized.map((item) => item.value), ['😂', '🤝']);
    expect(
      frequentExpressionItems(normalized).take(3).map((item) => item.value),
      ['🤝', '😂', '😊'],
    );
  });

  test('使用次数持久化时按 Server 和账号隔离', () async {
    const first = MessageCacheScope(
      serverUrl: 'https://chat.example.com',
      userId: 'user-1',
    );
    const second = MessageCacheScope(
      serverUrl: 'https://chat.example.com',
      userId: 'user-2',
    );
    final now = DateTime.utc(2026, 9, 7, 12);
    final usage = updateExpressionUsage(const [], '🤝', now);
    await const ExpressionUsageStore(first).write(usage);

    expect(
      (await const ExpressionUsageStore(first).read(now: now)).single.value,
      '🤝',
    );
    expect(await const ExpressionUsageStore(second).read(now: now), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(
      jsonDecode(preferences.getString(expressionUsageStorageKey(first))!),
      [
        {'value': '🤝', 'count': 1, 'last_used_at': now.millisecondsSinceEpoch},
      ],
    );
  });

  test('读取记录会清理未知表情和超过 30 天的项目', () async {
    const scope = MessageCacheScope(
      serverUrl: 'https://chat.example.com',
      userId: 'user-1',
    );
    final now = DateTime.utc(2026, 9, 7, 12);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      expressionUsageStorageKey(scope),
      jsonEncode([
        {
          'value': '😂',
          'count': 2,
          'last_used_at': now.millisecondsSinceEpoch,
        },
        {
          'value': '⭐',
          'count': 9,
          'last_used_at': now.millisecondsSinceEpoch,
        },
        {
          'value': '🤝',
          'count': 3,
          'last_used_at':
              now.subtract(const Duration(days: 31)).millisecondsSinceEpoch,
        },
      ]),
    );

    final usage = await const ExpressionUsageStore(scope).read(now: now);

    expect(usage.map((item) => item.value), ['😂']);
    expect(
      jsonDecode(preferences.getString(expressionUsageStorageKey(scope))!),
      [
        {
          'value': '😂',
          'count': 2,
          'last_used_at': now.millisecondsSinceEpoch,
        },
      ],
    );
  });

  testWidgets('选择器在手机和桌面宽度分别使用 6 列和 8 列', (tester) async {
    Future<void> pump(double width) => tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                height: 640,
                child: ExpressionPicker(onSelect: (_) {}),
              ),
            ),
          ),
        );

    await pump(280);
    await tester.pump(const Duration(milliseconds: 500));
    var allGrid = tester.widget<GridView>(
      find.byKey(const ValueKey('expression-section-所有表情')),
    );
    expect(allGrid.childrenDelegate.estimatedChildCount, 64);
    expect(
      (allGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      6,
    );
    expect(find.byTooltip('握手'), findsOneWidget);

    await pump(400);
    await tester.pump(const Duration(milliseconds: 500));
    allGrid = tester.widget<GridView>(
      find.byKey(const ValueKey('expression-section-所有表情')),
    );
    expect(
      (allGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      8,
    );
  });

  testWidgets('聊天选择表情替换当前选区并恢复光标和焦点', (tester) async {
    const scope = MessageCacheScope(
      serverUrl: 'https://chat.example.com',
      userId: 'user-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationView(
            repository: DemoRepository(),
            cacheScope: scope,
            conversationId: 'conversation-1',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final composer = find.byType(TextField).first;
    await tester.tap(composer);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好世界',
        selection: TextSelection(baseOffset: 2, extentOffset: 4),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('选择表情'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final laugh = find.byKey(const ValueKey('expression-常用-笑哭'));
    expect(tester.widget<IconButton>(laugh).onPressed, isNotNull);
    expect(laugh.hitTestable(), findsOneWidget);
    await tester.tap(laugh);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final value = tester.widget<TextField>(composer).controller!.value;
    expect(value.text, '你好😂');
    expect(value.selection, const TextSelection.collapsed(offset: 4));
    expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
    expect(find.byType(ExpressionPicker), findsNothing);

    final usage = await const ExpressionUsageStore(scope).read();
    expect(usage.single.value, '😂');
    expect(usage.single.count, 1);
  });
}
