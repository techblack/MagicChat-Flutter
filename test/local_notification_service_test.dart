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
  });

  test('权限被系统拒绝时返回 false 并不发送通知', () async {
    const channel = MethodChannel('test/magicchat/notifications-denied');
    var showCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermission') return false;
      if (call.method == 'showMessage') showCalled = true;
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    const service = LocalNotificationService(channel: channel);
    expect(await service.requestPermission(), isFalse);
    await service.showMessage(conversationId: 'c1', title: '测试', body: '正文');
    expect(showCalled, isFalse);
  });
}
