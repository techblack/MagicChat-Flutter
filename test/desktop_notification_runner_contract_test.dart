import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Runner 显示系统通知并回传消息路由', () async {
    final source =
        await File('windows/runner/flutter_window.cpp').readAsString();

    expect(source, contains('"magicchat/notifications"'));
    expect(source, contains('Shell_NotifyIconW(NIM_MODIFY'));
    expect(source, contains('NIN_BALLOONUSERCLICK'));
    expect(source, contains('"routeOpened"'));
    expect(source, contains('"conversation_id"'));
    expect(source, contains('"message_id"'));
  });

  test('macOS Runner 显示系统通知并回传消息路由', () async {
    final source = await File('macos/Runner/AppDelegate.swift').readAsString();

    expect(source, contains('"magicchat/notifications"'));
    expect(source, contains('UNNotificationRequest'));
    expect(source, contains('didReceive response: UNNotificationResponse'));
    expect(source, contains('"routeOpened"'));
    expect(source, contains('"conversation_id"'));
    expect(source, contains('"message_id"'));
  });

  test('Linux Runner 显示系统通知并回传消息路由', () async {
    final source = await File('linux/runner/my_application.cc').readAsString();

    expect(source, contains('"magicchat/notifications"'));
    expect(source, contains('"org.freedesktop.Notifications"'));
    expect(source, contains('"ActionInvoked"'));
    expect(source, contains('"routeOpened"'));
    expect(source, contains('"conversation_id"'));
    expect(source, contains('"message_id"'));
  });
}
