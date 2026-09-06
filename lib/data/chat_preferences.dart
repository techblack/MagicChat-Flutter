import 'package:shared_preferences/shared_preferences.dart';

enum MessageSendShortcut {
  enter,
  commandOrControlEnter,
}

enum MessageNotificationPrivacy { hidden, metadata, preview }

enum InterfaceFontScale { normal, medium, large }

extension InterfaceFontScaleValue on InterfaceFontScale {
  double get ratio => switch (this) {
        InterfaceFontScale.normal => 1,
        InterfaceFontScale.medium => 1.2,
        InterfaceFontScale.large => 1.3,
      };

  String get label => switch (this) {
        InterfaceFontScale.normal => '正常 100%',
        InterfaceFontScale.medium => '中等 120%',
        InterfaceFontScale.large => '较大 130%',
      };
}

class ChatPreferences {
  const ChatPreferences();

  static const sendShortcutKey = 'magicchat.chat.send-shortcut.v1';
  static const messageSoundKey = 'magicchat.chat.message-sound.v1';
  static const notificationPrivacyKey =
      'magicchat.chat.notification-privacy.v1';
  static const interfaceFontScaleKey = 'magicchat.interface.font-scale.v1';

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

  Future<bool> readMessageSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(messageSoundKey) ?? true;
  }

  Future<void> writeMessageSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(messageSoundKey, enabled);
  }

  Future<MessageNotificationPrivacy> readNotificationPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    return MessageNotificationPrivacy.values.firstWhere(
      (value) => value.name == prefs.getString(notificationPrivacyKey),
      orElse: () => MessageNotificationPrivacy.preview,
    );
  }

  Future<void> writeNotificationPrivacy(
      MessageNotificationPrivacy privacy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(notificationPrivacyKey, privacy.name);
  }

  Future<InterfaceFontScale> readInterfaceFontScale() async {
    final prefs = await SharedPreferences.getInstance();
    return InterfaceFontScale.values.firstWhere(
      (value) => value.name == prefs.getString(interfaceFontScaleKey),
      orElse: () => InterfaceFontScale.normal,
    );
  }

  Future<void> writeInterfaceFontScale(InterfaceFontScale scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(interfaceFontScaleKey, scale.name);
  }
}
