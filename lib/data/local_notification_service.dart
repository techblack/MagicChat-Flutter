import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser_notification_stub.dart'
    if (dart.library.js_interop) 'browser_notification_web.dart';

enum NotificationPermissionStatus {
  granted,
  denied,
  notDetermined,
  unsupported,
  unknown,
}

/// 统一通知桥接。原生端可实现 `magicchat/notifications`，未实现时保持静默，
/// 不影响 Web、Linux 或无通知权限的运行环境。
class LocalNotificationService {
  static const channelName = 'magicchat/notifications';

  const LocalNotificationService(
      {MethodChannel channel = const MethodChannel(channelName)})
      : _channel = channel;
  final MethodChannel _channel;

  Future<NotificationPermissionStatus> permissionStatus() async {
    if (kIsWeb && _channel.name == channelName) {
      return _parsePermissionStatus(browserNotificationPermissionStatus());
    }
    try {
      final value = await _channel.invokeMethod<Object?>('getPermissionStatus');
      return value is String
          ? _parsePermissionStatus(value)
          : NotificationPermissionStatus.unknown;
    } on MissingPluginException {
      return NotificationPermissionStatus.unsupported;
    } on PlatformException {
      return NotificationPermissionStatus.unknown;
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb && _channel.name == channelName) {
      return browserNotificationRequestPermission();
    }
    try {
      final value = await _channel.invokeMethod<Object?>('requestPermission');
      return value is bool ? value : true;
    } on MissingPluginException {
      // Platforms without a native notification adapter remain usable.
      return true;
    } on PlatformException {
      // Permission denial is represented by the platform and is non-fatal.
      return false;
    }
  }

  Future<void> showMessage({
    required String conversationId,
    required String title,
    required String body,
    String messageId = '',
  }) async {
    if (kIsWeb && _channel.name == channelName) {
      await browserNotificationShow(
          title: title,
          body: body,
          tag: conversationId,
          conversationId: conversationId,
          messageId: messageId);
      return;
    }
    try {
      if (!await requestPermission()) return;
      await _channel.invokeMethod<void>('showMessage', {
        'conversation_id': conversationId,
        'message_id': messageId,
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // Web/Linux without a notification adapter are valid fallback targets.
    } on PlatformException {
      // Permission or provider failures must not interrupt message sync.
    }
  }
}

NotificationPermissionStatus _parsePermissionStatus(String value) =>
    switch (value) {
      'granted' => NotificationPermissionStatus.granted,
      'denied' => NotificationPermissionStatus.denied,
      'default' ||
      'notDetermined' =>
        NotificationPermissionStatus.notDetermined,
      'unsupported' => NotificationPermissionStatus.unsupported,
      _ => NotificationPermissionStatus.unknown,
    };
