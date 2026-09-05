import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> browserNotificationRequestPermission() async {
  final current = web.Notification.permission;
  if (current == 'granted') return true;
  if (current == 'denied') return false;
  final permission = await web.Notification.requestPermission().toDart;
  return permission == 'granted';
}

Future<bool> browserNotificationShow({
  required String title,
  required String body,
  required String tag,
}) async {
  if (!await browserNotificationRequestPermission()) return false;
  web.Notification(
      title, web.NotificationOptions(body: body, tag: tag, silent: true));
  return true;
}
