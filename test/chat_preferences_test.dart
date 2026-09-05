import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('发送快捷键默认使用 Enter 并可持久化替代预设', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ChatPreferences();

    expect(await preferences.readSendShortcut(), MessageSendShortcut.enter);

    await preferences
        .writeSendShortcut(MessageSendShortcut.commandOrControlEnter);
    expect(await preferences.readSendShortcut(),
        MessageSendShortcut.commandOrControlEnter);
  });

  test('未知发送快捷键值回退到 Enter', () async {
    SharedPreferences.setMockInitialValues({
      ChatPreferences.sendShortcutKey: 'invalid',
    });

    expect(await const ChatPreferences().readSendShortcut(),
        MessageSendShortcut.enter);
  });

  test('新消息提示音默认开启并可持久化关闭', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ChatPreferences();
    expect(await preferences.readMessageSoundEnabled(), isTrue);
    await preferences.writeMessageSoundEnabled(false);
    expect(await preferences.readMessageSoundEnabled(), isFalse);
  });
}
