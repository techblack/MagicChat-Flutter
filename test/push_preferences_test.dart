import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/push_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('JPush 默认未获授权且授权状态可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = PushPreferences();

    expect(await preferences.readJPushConsent(), isFalse);
    await preferences.writeJPushConsent(true);
    expect(await preferences.readJPushConsent(), isTrue);
    await preferences.writeJPushConsent(false);
    expect(await preferences.readJPushConsent(), isFalse);
  });
}
