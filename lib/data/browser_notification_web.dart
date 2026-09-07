import 'dart:js_interop';

import 'package:web/web.dart' as web;

String browserNotificationPermissionStatus() => web.Notification.permission;

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
  required String conversationId,
  required String messageId,
}) async {
  if (browserNotificationPermissionStatus() != 'granted') return false;
  final notification = web.Notification(
      title, web.NotificationOptions(body: body, tag: tag, silent: true));
  void handleClick(web.Event _) {
    final current = Uri.parse(web.window.location.href);
    final query = <String, String>{
      ...current.queryParameters,
      'conversation_id': conversationId,
      if (messageId.isNotEmpty) 'message_id': messageId,
    };
    web.window.location.href =
        current.replace(queryParameters: query).toString();
  }

  notification.onclick = handleClick.toJS;
  return true;
}
