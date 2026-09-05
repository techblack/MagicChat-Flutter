import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/features/qr_content.dart';
import 'package:magicchat_client/features/qr_result_page.dart';
import 'package:magicchat_client/features/qr_scanner_page.dart';
import 'package:magicchat_client/features/qr_webview_page.dart';

void main() {
  test('二维码内容只将完整 HTTP(S) 地址识别为网页', () {
    final secure = classifyQrContent('  https://example.com/docs?q=1  ');
    final insecure = classifyQrContent('http://example.com');
    final text = classifyQrContent('  普通文本  ');

    expect(secure.kind, QrContentKind.web);
    expect(secure.value, 'https://example.com/docs?q=1');
    expect(insecure.kind, QrContentKind.web);
    expect(text.kind, QrContentKind.text);
    expect(text.value, '  普通文本  ');
    expect(classifyQrContent('javascript:alert(1)').kind, QrContentKind.text);
    expect(classifyQrContent('//example.com/path').kind, QrContentKind.text);
    expect(classifyQrContent('https:example.com').kind, QrContentKind.text);
  });

  test('内置网页导航仅允许 HTTP(S)', () {
    expect(isAllowedQrWebUri(Uri.parse('https://example.com')), isTrue);
    expect(isAllowedQrWebUri(Uri.parse('http://example.com/path')), isTrue);
    expect(isAllowedQrWebUri(Uri.parse('file:///tmp/page.html')), isFalse);
    expect(isAllowedQrWebUri(Uri.parse('data:text/html,hello')), isFalse);
  });

  test('扫描内容进入对应结果页面', () {
    expect(buildQrScanDestination('https://example.com'), isA<QrWebViewPage>());
    expect(buildQrScanDestination('设备配对码'), isA<QrResultPage>());
  });

  testWidgets('文本扫描结果可选择复制并再次扫描', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
      home: QrResultPage(
        content: '设备配对码：123456',
        scanAgainBuilder: (_) => const Scaffold(body: Text('新的扫描页')),
      ),
    ));

    expect(find.text('扫描结果'), findsOneWidget);
    expect(find.text('设备配对码：123456'), findsOneWidget);
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(find.text('扫描结果已复制'), findsOneWidget);

    await tester.tap(find.text('再次扫描'));
    await tester.pumpAndSettle();
    expect(find.text('新的扫描页'), findsOneWidget);
  });

  testWidgets('不支持内置网页的平台提供复制和外部浏览器入口', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(const MaterialApp(
      home: QrWebViewPage(url: 'https://example.com/docs'),
    ));
    await tester.pump();

    expect(find.text('当前平台暂不支持内置网页'), findsOneWidget);
    expect(find.text('https://example.com/docs'), findsOneWidget);
    expect(find.text('复制地址'), findsOneWidget);
    expect(find.text('在浏览器里打开'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('无效网页地址显示可读错误', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: QrWebViewPage(url: 'javascript:alert(1)'),
    ));

    expect(find.text('无法打开网页'), findsOneWidget);
    expect(find.text('二维码中的链接无效或不受支持'), findsOneWidget);
    final externalButton = find.ancestor(
        of: find.byTooltip('在浏览器里打开'), matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(externalButton).onPressed, isNull);
  });
}
