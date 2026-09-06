import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天视觉皮肤。颜色只用于本地渲染，不会改变服务端消息数据。
enum ChatSkin { classic, ocean, forest, sunset, lavender }

enum ChatBackground { plain, mist, midnight, paper }

enum ChatBubbleSkin { solid, outline, soft }

extension ChatSkinLabel on ChatSkin {
  String get label => switch (this) {
        ChatSkin.classic => '经典蓝',
        ChatSkin.ocean => '海洋青',
        ChatSkin.forest => '森林绿',
        ChatSkin.sunset => '落日橙',
        ChatSkin.lavender => '薰衣草',
      };

  Color get seedColor => switch (this) {
        ChatSkin.classic => const Color(0xff3a76f0),
        ChatSkin.ocean => const Color(0xff087e8b),
        ChatSkin.forest => const Color(0xff3f7d45),
        ChatSkin.sunset => const Color(0xffc46132),
        ChatSkin.lavender => const Color(0xff7653a6),
      };
}

extension ChatBackgroundLabel on ChatBackground {
  String get label => switch (this) {
        ChatBackground.plain => '纯色',
        ChatBackground.mist => '雾蓝',
        ChatBackground.midnight => '夜幕',
        ChatBackground.paper => '纸张',
      };
}

extension ChatBubbleSkinLabel on ChatBubbleSkin {
  String get label => switch (this) {
        ChatBubbleSkin.solid => '实心',
        ChatBubbleSkin.outline => '描边',
        ChatBubbleSkin.soft => '柔和',
      };
}

class ChatAppearance {
  const ChatAppearance({
    this.skin = ChatSkin.classic,
    this.background = ChatBackground.plain,
    this.bubble = ChatBubbleSkin.solid,
    this.fontSize = 14,
  });

  final ChatSkin skin;

  /// 默认聊天背景；单独会话的设置会覆盖这个值。
  final ChatBackground background;

  /// 默认聊天气泡；单独会话的设置会覆盖这个值。
  final ChatBubbleSkin bubble;
  final double fontSize;

  ChatAppearance copyWith({
    ChatSkin? skin,
    ChatBackground? background,
    ChatBubbleSkin? bubble,
    double? fontSize,
  }) =>
      ChatAppearance(
        skin: skin ?? this.skin,
        background: background ?? this.background,
        bubble: bubble ?? this.bubble,
        fontSize: fontSize ?? this.fontSize,
      );
}

class ChatConversationAppearance {
  const ChatConversationAppearance({
    this.background = ChatBackground.plain,
    this.bubble = ChatBubbleSkin.solid,
  });

  final ChatBackground background;
  final ChatBubbleSkin bubble;

  ChatConversationAppearance copyWith({
    ChatBackground? background,
    ChatBubbleSkin? bubble,
  }) =>
      ChatConversationAppearance(
        background: background ?? this.background,
        bubble: bubble ?? this.bubble,
      );
}

class ChatAppearancePreferences {
  const ChatAppearancePreferences();

  static const skinKey = 'magicchat.chat.appearance.skin.v1';
  static const backgroundKey = 'magicchat.chat.appearance.background.v1';
  static const bubbleKey = 'magicchat.chat.appearance.bubble.v1';
  static const fontSizeKey = 'magicchat.chat.appearance.font-size.v1';
  static const conversationPrefix =
      'magicchat.chat.appearance.conversation.v1.';

  Future<ChatAppearance> readGlobal() async {
    final prefs = await SharedPreferences.getInstance();
    final skin = ChatSkin.values.firstWhere(
      (value) => value.name == prefs.getString(skinKey),
      orElse: () => ChatSkin.classic,
    );
    final background = ChatBackground.values.firstWhere(
      (value) => value.name == prefs.getString(backgroundKey),
      orElse: () => ChatBackground.plain,
    );
    final bubble = ChatBubbleSkin.values.firstWhere(
      (value) => value.name == prefs.getString(bubbleKey),
      orElse: () => ChatBubbleSkin.solid,
    );
    final value = prefs.getDouble(fontSizeKey) ?? 15;
    return ChatAppearance(
        skin: skin,
        background: background,
        bubble: bubble,
        fontSize: value.clamp(12, 24));
  }

  Future<void> writeGlobal(ChatAppearance appearance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(skinKey, appearance.skin.name);
    await prefs.setString(backgroundKey, appearance.background.name);
    await prefs.setString(bubbleKey, appearance.bubble.name);
    await prefs.setDouble(fontSizeKey, appearance.fontSize.clamp(12, 24));
  }

  Future<ChatConversationAppearance> readConversation(String conversationId,
      {ChatConversationAppearance fallback =
          const ChatConversationAppearance()}) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$conversationPrefix$conversationId.';
    final background = ChatBackground.values.firstWhere(
      (value) => value.name == prefs.getString('${prefix}background'),
      orElse: () => fallback.background,
    );
    final bubble = ChatBubbleSkin.values.firstWhere(
      (value) => value.name == prefs.getString('${prefix}bubble'),
      orElse: () => fallback.bubble,
    );
    return ChatConversationAppearance(background: background, bubble: bubble);
  }

  Future<ChatConversationAppearance?> readConversationOverride(
      String conversationId,
      {ChatConversationAppearance fallback =
          const ChatConversationAppearance()}) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$conversationPrefix$conversationId.';
    if (!prefs.containsKey('${prefix}background') &&
        !prefs.containsKey('${prefix}bubble')) {
      return null;
    }
    return readConversation(conversationId, fallback: fallback);
  }

  Future<void> writeConversation(
      String conversationId, ChatConversationAppearance appearance) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$conversationPrefix$conversationId.';
    await prefs.setString('${prefix}background', appearance.background.name);
    await prefs.setString('${prefix}bubble', appearance.bubble.name);
  }
}
