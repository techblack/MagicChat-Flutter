import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('默认 Enter 发送而 Shift+Enter 保留给换行', (tester) async {
    final repository = _ShortcutRepository();
    await _pump(tester, repository, MessageSendShortcut.enter);
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '第一条');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(repository.sentMessages, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(repository.sentMessages, ['第一条']);
  });

  testWidgets('可配置 Ctrl 或 Command 加 Enter 发送', (tester) async {
    final repository = _ShortcutRepository();
    await _pump(tester, repository, MessageSendShortcut.commandOrControlEnter);
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '快捷发送');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(repository.sentMessages, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(repository.sentMessages, ['快捷发送']);
  });

  testWidgets('输入法仍在组合文本时 Enter 不发送', (tester) async {
    final repository = _ShortcutRepository();
    await _pump(tester, repository, MessageSendShortcut.enter);
    final field = find.byType(TextField);
    await tester.tap(field);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '拼音',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(repository.sentMessages, isEmpty);
  });
}

Future<void> _pump(WidgetTester tester, _ShortcutRepository repository,
    MessageSendShortcut shortcut) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ConversationView(
        repository: repository,
        conversationId: 'conversation-1',
        sendMessageShortcut: shortcut,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

class _ShortcutRepository extends DemoRepository {
  final sentMessages = <String>[];

  @override
  Future<void> sendMessage(String conversationId, String text,
      {String? replyToMessageId}) async {
    sentMessages.add(text);
  }
}
