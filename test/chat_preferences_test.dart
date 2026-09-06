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

  test('通知隐私默认显示预览并可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ChatPreferences();
    expect(await preferences.readNotificationPrivacy(),
        MessageNotificationPrivacy.preview);
    await preferences
        .writeNotificationPrivacy(MessageNotificationPrivacy.metadata);
    expect(await preferences.readNotificationPrivacy(),
        MessageNotificationPrivacy.metadata);
  });

  test('界面字体缩放默认正常并可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ChatPreferences();
    expect(
        await preferences.readInterfaceFontScale(), InterfaceFontScale.normal);
    await preferences.writeInterfaceFontScale(InterfaceFontScale.large);
    expect(
        await preferences.readInterfaceFontScale(), InterfaceFontScale.large);
    expect(InterfaceFontScale.medium.ratio, 1.2);
    expect(InterfaceFontScale.large.label, '较大 130%');
  });
}
