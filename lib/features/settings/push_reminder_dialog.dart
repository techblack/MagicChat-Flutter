import 'package:flutter/material.dart';

import '../../data/push_reminder.dart';

Future<bool?> showPushReminderDialog(
  BuildContext context,
  PushReminderKind kind, {
  required Future<void> Function() onEnable,
  required Future<bool> Function() onRequestPermission,
}) {
  final consent = kind == PushReminderKind.consent;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(consent ? '启用手机通知' : '开启系统通知'),
      content: Text(consent
          ? 'Android 通知由极光推送提供。启用后，极光 SDK 会处理完成通知投递所需的设备、系统、网络和应用标识信息；不会收到聊天账号、服务器地址或消息内容。'
          : '系统通知权限或“消息通知”渠道尚未开启，开启后才能在后台收到新消息提醒。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(consent ? '暂不启用' : '暂不提醒'),
        ),
        FilledButton(
          onPressed: () async {
            final enabled = consent ? true : await onRequestPermission();
            if (!enabled) {
              if (dialogContext.mounted) Navigator.pop(dialogContext, false);
              return;
            }
            if (consent) await onEnable();
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          },
          child: Text(consent ? '同意并启用' : '去开启'),
        ),
      ],
    ),
  );
}
