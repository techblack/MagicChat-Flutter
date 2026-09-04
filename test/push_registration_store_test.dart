import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/push_registration_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};

  setUp(() {
    values.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return key == null ? null : values[key];
        case 'write':
          if (key != null) values[key] = args['value'] as String;
          return null;
        case 'delete':
          if (key != null) values.remove(key);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('安全存储往返推送安装和授权凭据', () async {
    const store = PushRegistrationStore();
    await store.writeInstallation(StoredPushInstallation(
        installationId: 'install-1',
        managementToken: 'manage-1',
        provider: 'apns',
        platform: 'ios',
        environment: 'production',
        providerToken: 'a' * 64,
        appVersion: '0.1.0'));
    await store.writeGrant(StoredPushGrant(
        grantId: 'grant-1',
        sendToken: 'send-1',
        expiresAt: DateTime.utc(2999),
        installationId: 'install-1',
        serverUrl: 'https://chat.example.com'));

    final installation = await store.readInstallation();
    final grant = await store.readGrant();
    expect(installation?.installationId, 'install-1');
    expect(installation?.providerToken, 'a' * 64);
    expect(grant?.grantId, 'grant-1');
    expect(grant?.serverUrl, 'https://chat.example.com');

    await store.clearGrant();
    expect(await store.readGrant(), isNull);
  });
}
