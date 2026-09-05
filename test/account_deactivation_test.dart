import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicchat_client/data/auth_service.dart';
import 'package:magicchat_client/data/session_store.dart';
import 'package:magicchat_client/features/settings/account_deactivation_page.dart';

class _MemorySessionStore extends SessionStore {
  String? token = 'session-token';

  @override
  Future<String?> readToken() async => token;
}

void main() {
  testWidgets('注销账号页面视觉基线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('account-deactivation-golden'),
      child: SizedBox(
        width: 600,
        height: 800,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: AccountDeactivationPage(
            serverUrl: 'https://chat.example.com',
            email: 'alice@example.com',
            onDeactivate: (_) async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('account-deactivation-golden')),
      matchesGoldenFile('evidence/account_deactivation.png'),
    );
  });

  testWidgets('注销页发送验证码、过滤输入并提交 8 位验证码', (tester) async {
    late http.Request codeRequest;
    String? submittedCode;
    final service = AuthService(
      sessions: _MemorySessionStore(),
      client: MockClient((request) async {
        codeRequest = request;
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'expires_in_seconds': 900,
                'retry_after_seconds': 60,
              },
            }),
            200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: AccountDeactivationPage(
        serverUrl: 'https://chat.example.com',
        email: 'alice@example.com',
        authService: service,
        onDeactivate: (code) async => submittedCode = code,
      ),
    ));

    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.textContaining('无法恢复'), findsOneWidget);
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(codeRequest.url.path, '/api/client/me/deactivation/code');
    expect(find.text('60 秒'), findsOneWidget);
    expect(find.textContaining('900 秒内有效'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('account-deactivation-code')),
        '12ab 3456-789');
    await tester.pump();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('account-deactivation-code')))
            .controller
            ?.text,
        '12345678');
    await tester.tap(find.widgetWithText(FilledButton, '注销账号'));
    await tester.pumpAndSettle();

    expect(submittedCode, '12345678');
  });

  testWidgets('明确的错误验证码保留注销页面并显示服务端原因', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AccountDeactivationPage(
        serverUrl: 'https://chat.example.com',
        email: 'alice@example.com',
        onDeactivate: (_) async => throw const AuthRequestException('验证码错误',
            code: 'invalid_code', statusCode: 401),
      ),
    ));

    await tester.enterText(
        find.byKey(const ValueKey('account-deactivation-code')), '12345678');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '注销账号'));
    await tester.pumpAndSettle();

    expect(find.text('注销账号'), findsWidgets);
    expect(find.text('验证码错误'), findsOneWidget);
  });
}
