Future<bool> browserNotificationRequestPermission() async => false;

Future<bool> browserNotificationShow({
  required String title,
  required String body,
  required String tag,
  required String conversationId,
  required String messageId,
}) async =>
    false;
