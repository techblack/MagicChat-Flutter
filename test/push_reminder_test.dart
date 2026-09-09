import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/push_reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final promptedAt = DateTime.utc(2026, 9, 9, 12);

  test('新版本或冷却期后显示提醒', () {
    final state = recordPushReminder(
      const PushReminderState(),
      PushReminderKind.permission,
      '1.0.0',
      now: promptedAt,
    );

    expect(
      shouldShowPushReminder(
        state: state,
        kind: PushReminderKind.permission,
        appVersion: '1.0.0',
        now: promptedAt.add(const Duration(days: 6, hours: 23)),
      ),
      isFalse,
    );
    expect(
      shouldShowPushReminder(
        state: state,
        kind: PushReminderKind.permission,
        appVersion: '1.0.1',
        now: promptedAt,
      ),
      isTrue,
    );
    expect(
      shouldShowPushReminder(
        state: state,
        kind: PushReminderKind.permission,
        appVersion: '1.0.0',
        now: promptedAt.add(const Duration(days: 7)),
      ),
      isTrue,
    );
  });

  test('同意后清除对应提醒，显式关闭后不再提示', () {
    final state = recordPushReminder(
      const PushReminderState(),
      PushReminderKind.consent,
      '1.0.0',
      now: promptedAt,
    );
    final cleared = clearPushReminder(state, PushReminderKind.consent);
    expect(cleared.prompts, isEmpty);

    final disabled = cleared.copyWith(explicitlyDisabled: true);
    expect(
      shouldShowPushReminder(
        state: disabled,
        kind: PushReminderKind.consent,
        appVersion: '1.0.0',
        now: promptedAt,
      ),
      isFalse,
    );
  });

  test('提醒状态可持久化并保留两类提醒', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = PushReminderPreferences();
    var state = recordPushReminder(
      const PushReminderState(),
      PushReminderKind.consent,
      '1.0.0',
      now: promptedAt,
    );
    state = recordPushReminder(
      state,
      PushReminderKind.permission,
      '1.0.0',
      now: promptedAt,
    );
    await preferences.write(state.copyWith(explicitlyDisabled: true));

    final restored = await preferences.read();
    expect(restored.explicitlyDisabled, isTrue);
    expect(restored.prompts.keys,
        containsAll([PushReminderKind.consent, PushReminderKind.permission]));
    expect(restored.prompts[PushReminderKind.permission]?.appVersion, '1.0.0');
  });
}
