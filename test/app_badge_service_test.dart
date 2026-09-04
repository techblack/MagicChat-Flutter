import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/app_badge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('系统角标把负数规范为零并传递未读数', () async {
    const channel = MethodChannel('test/magicchat/app-badge');
    final counts = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setCount');
      counts.add((call.arguments as Map)['count'] as int);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    const service = AppBadgeService(channel: channel);
    await service.setCount(7);
    await service.setCount(-1);

    expect(counts, [7, 0]);
  });
}
