Future<bool> browserNotificationRequestPermission() async => false;

String browserNotificationPermissionStatus() => 'unsupported';

Future<bool> browserNotificationShow({
  required String title,
  required String body,
  required String tag,
  required String conversationId,
  required String messageId,
}) async =>
    false;
