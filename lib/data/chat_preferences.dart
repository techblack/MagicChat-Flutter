import 'package:shared_preferences/shared_preferences.dart';

enum MessageSendShortcut {
  enter,
  commandOrControlEnter,
}

class ChatPreferences {
  const ChatPreferences();

  static const sendShortcutKey = 'magicchat.chat.send-shortcut.v1';

  Future<MessageSendShortcut> readSendShortcut() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(sendShortcutKey)) {
      'commandOrControlEnter' => MessageSendShortcut.commandOrControlEnter,
      _ => MessageSendShortcut.enter,
    };
  }

  Future<void> writeSendShortcut(MessageSendShortcut shortcut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sendShortcutKey, shortcut.name);
  }
}
