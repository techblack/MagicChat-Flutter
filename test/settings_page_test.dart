import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('设置页展示账户、服务器、通知与存储入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1042, 662));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('settings-page-golden'),
        child: SizedBox(
          width: 1042,
          height: 662,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
                useMaterial3: true),
            home: Scaffold(
              appBar: AppBar(title: const Text('设置')),
              body: SettingsPage(
                repository: DemoRepository(),
                serverUrl: 'https://chat.example.com',
                onLogout: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('演示用户'), findsOneWidget);
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);
    expect(find.text('存储空间'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);

    await expectLater(
      find.byKey(const ValueKey('settings-page-golden')),
      matchesGoldenFile('evidence/settings_page.png'),
    );

    await tester.scrollUntilVisible(find.text('退出登录'), 500,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('退出登录'), findsOneWidget);
  });
}
