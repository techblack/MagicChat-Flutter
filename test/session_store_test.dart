import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/session_store.dart';

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

  test('会话失效时仅标记匹配账户并保留重新登录入口', () async {
    const store = SessionStore();
    await store.saveAccount(const StoredAccount(
        id: 'one',
        serverUrl: 'https://one.example.com',
        token: 'token-one',
        email: 'one@example.com'));
    await store.saveAccount(const StoredAccount(
        id: 'two',
        serverUrl: 'https://two.example.com',
        token: 'token-two',
        email: 'two@example.com'));

    await store.markAccountReauthRequired(
        serverUrl: 'https://one.example.com', token: 'token-one');

    final accounts = await store.readAccounts();
    expect(accounts.map((account) => account.status),
        ['reauth-required', 'ready']);
    expect(jsonDecode(values['magicchat.accounts']!), isA<List>());
  });
}
