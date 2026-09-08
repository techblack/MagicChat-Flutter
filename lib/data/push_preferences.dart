import 'package:shared_preferences/shared_preferences.dart';

/// 本机推送授权偏好。JPush 需要在隐私说明确认后才允许初始化。
class PushPreferences {
  const PushPreferences();

  static const jpushConsentKey = 'magicchat.push.jpush-consent.v1';

  Future<bool> readJPushConsent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(jpushConsentKey) ?? false;
  }

  Future<void> writeJPushConsent(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(jpushConsentKey, enabled);
  }
}
