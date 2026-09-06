import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/app_links.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/update_service.dart';
import 'package:magicchat_client/features/settings/about_magicchat_page.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('设置页打开关于页面并返回原设置页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: SettingsPage(
          repository: DemoRepository(),
          serverUrl: 'https://chat.example.com',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('关于 MagicChat'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('关于 MagicChat'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutMagicChatPage), findsOneWidget);
    expect(
        find.text('版本 ${UpdateService.currentVersion} · 构建 '
            '${UpdateService.currentBuild}'),
        findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AboutMagicChatPage), findsNothing);
    expect(find.text('关于 MagicChat'), findsOneWidget);
  });

  testWidgets('桌面布局展示品牌版本平台并安全打开外链', (tester) async {
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: AboutMagicChatPage(
        version: '1.2.3',
        buildNumber: 45,
        isWeb: false,
        platform: TargetPlatform.windows,
        linkLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about-brand-wide')), findsOneWidget);
    expect(find.text('MagicChat'), findsWidgets);
    expect(find.text('版本 1.2.3 · 构建 45'), findsOneWidget);
    expect(find.text('运行平台 · Windows'), findsOneWidget);
    expect(find.bySemanticsLabel('MagicChat 图标'), findsOneWidget);

    for (final label in ['用户协议', '隐私政策', '项目主页', 'Release 页面']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(launched, [
      Uri.parse(magicChatUserAgreementUrl),
      Uri.parse(magicChatPrivacyPolicyUrl),
      Uri.parse(magicChatProjectUrl),
      Uri.parse(magicChatReleasesUrl),
    ]);
  });

  testWidgets('窄屏内容不溢出且开源许可返回关于页面', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: AboutMagicChatPage(
        version: '1.2.3',
        buildNumber: 45,
        isWeb: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about-brand-compact')), findsOneWidget);
    expect(find.text('运行平台 · Web'), findsOneWidget);
    expect(find.bySemanticsLabel('MagicChat 图标'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('开源许可'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('1.2.3+45'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AboutMagicChatPage), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('外链打开失败显示可读提示并停留当前页面', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutMagicChatPage(
        linkLauncher: (_) async => false,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法打开隐私政策，请稍后重试'), findsOneWidget);
    expect(find.byType(AboutMagicChatPage), findsOneWidget);
  });

  test('平台名称不读取内部路径或设备凭据', () {
    expect(
        magicChatPlatformLabel(isWeb: false, platform: TargetPlatform.android),
        'Android');
    expect(magicChatPlatformLabel(isWeb: false, platform: TargetPlatform.macOS),
        'macOS');
    expect(
        magicChatPlatformLabel(isWeb: true, platform: TargetPlatform.windows),
        'Web');
  });
}
