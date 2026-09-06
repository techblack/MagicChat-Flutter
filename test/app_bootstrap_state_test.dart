import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/features/shared/app_bootstrap_state.dart';

void main() {
  testWidgets('品牌加载状态展示明确进度和工作空间说明', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLoadingView()));

    expect(find.text('正在启动 MagicChat'), findsOneWidget);
    expect(find.text('正在为你准备工作空间'), findsOneWidget);
    expect(find.byKey(const ValueKey('brand-loading-ring')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('brand-loading-progress')), findsOneWidget);
  });

  testWidgets('初始化错误页保留原因并提供重试', (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        home: AppInitializationErrorView(
            message: '无法读取安全存储', onRetry: () => retries++)));

    expect(find.text('无法打开工作空间'), findsOneWidget);
    expect(find.text('无法读取安全存储'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bootstrap-retry')));
    expect(retries, 1);
  });
}
