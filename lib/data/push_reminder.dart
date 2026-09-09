import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum PushReminderKind { consent, permission }

const pushReminderCooldown = Duration(days: 7);

class PushReminderRecord {
  const PushReminderRecord(
      {required this.appVersion, required this.promptedAt});

  final String appVersion;
  final DateTime promptedAt;
}

class PushReminderState {
  const PushReminderState(
      {this.explicitlyDisabled = false, this.prompts = const {}});

  final bool explicitlyDisabled;
  final Map<PushReminderKind, PushReminderRecord> prompts;

  PushReminderState copyWith({
    bool? explicitlyDisabled,
    Map<PushReminderKind, PushReminderRecord>? prompts,
  }) =>
      PushReminderState(
        explicitlyDisabled: explicitlyDisabled ?? this.explicitlyDisabled,
        prompts: prompts ?? this.prompts,
      );
}

bool shouldShowPushReminder({
  required PushReminderState state,
  required PushReminderKind kind,
  required String appVersion,
  DateTime? now,
}) {
  if (state.explicitlyDisabled) return false;
  final previous = state.prompts[kind];
  if (previous == null || previous.appVersion != appVersion) return true;
  return (now ?? DateTime.now()).difference(previous.promptedAt) >=
      pushReminderCooldown;
}

PushReminderState recordPushReminder(
  PushReminderState state,
  PushReminderKind kind,
  String appVersion, {
  DateTime? now,
}) {
  return state.copyWith(
    prompts: {
      ...state.prompts,
      kind: PushReminderRecord(
        appVersion: appVersion.trim(),
        promptedAt: now ?? DateTime.now(),
      ),
    },
  );
}

PushReminderState clearPushReminder(
    PushReminderState state, PushReminderKind kind) {
  if (!state.prompts.containsKey(kind)) return state;
  final prompts = {...state.prompts}..remove(kind);
  return state.copyWith(prompts: prompts);
}

class PushReminderPreferences {
  const PushReminderPreferences();

  static const key = 'magicchat.push.reminder.v1';

  Future<PushReminderState> read() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(key);
    if (encoded == null) return const PushReminderState();
    try {
      final value = jsonDecode(encoded);
      if (value is! Map) return const PushReminderState();
      final rawPrompts = value['prompts'];
      final prompts = <PushReminderKind, PushReminderRecord>{};
      if (rawPrompts is Map) {
        for (final kind in PushReminderKind.values) {
          final raw = rawPrompts[kind.name];
          if (raw is! Map ||
              raw['app_version'] is! String ||
              raw['prompted_at'] is! String) continue;
          final promptedAt = DateTime.tryParse(raw['prompted_at'] as String);
          if (promptedAt == null) continue;
          prompts[kind] = PushReminderRecord(
            appVersion: (raw['app_version'] as String).trim(),
            promptedAt: promptedAt,
          );
        }
      }
      return PushReminderState(
        explicitlyDisabled: value['explicitly_disabled'] == true,
        prompts: prompts,
      );
    } on FormatException {
      return const PushReminderState();
    }
  }

  Future<void> write(PushReminderState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'version': 1,
        'explicitly_disabled': state.explicitlyDisabled,
        'prompts': {
          for (final entry in state.prompts.entries)
            entry.key.name: {
              'app_version': entry.value.appVersion,
              'prompted_at': entry.value.promptedAt.toUtc().toIso8601String(),
            },
        },
      }),
    );
  }
}
