import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('无原生通知插件时安全降级', () async {
    const channel = MethodChannel('test/magicchat/notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await const LocalNotificationService(channel: channel)
        .showMessage(conversationId: 'c1', title: '测试', body: '正文');
    expect(
        await const LocalNotificationService(channel: channel)
            .permissionStatus(),
        NotificationPermissionStatus.unsupported);
  });

  test('读取通知权限状态不会触发授权请求', () async {
    const channel = MethodChannel('test/magicchat/notifications-status');
    var permissionRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermission') permissionRequests++;
      if (call.method == 'getPermissionStatus') return 'notDetermined';
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    expect(
        await const LocalNotificationService(channel: channel)
            .permissionStatus(),
        NotificationPermissionStatus.notDetermined);
    expect(permissionRequests, 0);
  });

  test('收到消息时只读权限状态且不主动请求授权', () async {
    const channel = MethodChannel('test/magicchat/notifications-denied');
    var showCalled = false;
    var permissionRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPermissionStatus') return 'denied';
      if (call.method == 'requestPermission') permissionRequests++;
      if (call.method == 'showMessage') showCalled = true;
      return false;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    const service = LocalNotificationService(channel: channel);
    await service.showMessage(conversationId: 'c1', title: '测试', body: '正文');
    expect(permissionRequests, 0);
    expect(showCalled, isFalse);
    expect(await service.requestPermission(), isFalse);
    expect(permissionRequests, 1);
  });

  test('本地消息通知携带会话和消息路由', () async {
    const channel = MethodChannel('test/magicchat/notifications-route');
    Map<Object?, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPermissionStatus') return 'granted';
      if (call.method == 'showMessage') {
        arguments = Map<Object?, Object?>.from(call.arguments as Map);
      }
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await const LocalNotificationService(channel: channel).showMessage(
        conversationId: 'c1', messageId: 'm1', title: 'Alice', body: '正文');

    expect(arguments?['conversation_id'], 'c1');
    expect(arguments?['message_id'], 'm1');
  });
}
