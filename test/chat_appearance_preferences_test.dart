import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/chat_appearance_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('全局皮肤和字号可持久化并限制范围', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ChatAppearancePreferences();
    await preferences
        .writeGlobal(const ChatAppearance(skin: ChatSkin.ocean, fontSize: 20));

    final value = await preferences.readGlobal();
    expect(value.skin, ChatSkin.ocean);
    expect(value.fontSize, 20);
  });

  test('单独会话背景和气泡皮肤互不影响全局设置', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ChatAppearancePreferences();
    await preferences.writeConversation(
        'group/1',
        const ChatConversationAppearance(
            background: ChatBackground.midnight,
            bubble: ChatBubbleSkin.outline));

    final value = await preferences.readConversation('group/1');
    expect(value.background, ChatBackground.midnight);
    expect(value.bubble, ChatBubbleSkin.outline);
    expect((await preferences.readConversation('other')).background,
        ChatBackground.plain);
  });
}
