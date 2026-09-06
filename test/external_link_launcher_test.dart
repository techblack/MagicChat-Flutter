import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/features/shared/external_link_launcher.dart';

void main() {
  testWidgets('HTTPS 链接直接交给系统浏览器', (tester) async {
    Uri? launched;
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await launchExternalWebLink(
              context,
              Uri.parse('https://example.com/docs'),
              launcher: (uri) async {
                launched = uri;
                return true;
              },
            );
          },
          child: const Text('打开'),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pump();

    expect(launched, Uri.parse('https://example.com/docs'));
    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('HTTP 链接展示域名和完整地址并等待确认', (tester) async {
    Uri? launched;
    bool? result;
    const url = 'http://intranet.example.test/docs?from=chat';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await launchExternalWebLink(
              context,
              Uri.parse(url),
              launcher: (uri) async {
                launched = uri;
                return true;
              },
            );
          },
          child: const Text('打开'),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(launched, isNull);
    expect(find.text('打开不安全的 HTTP 链接？'), findsOneWidget);
    expect(find.text('目标地址 · intranet.example.test'), findsOneWidget);
    expect(find.text(url), findsOneWidget);

    await tester.tap(find.text('继续打开'));
    await tester.pumpAndSettle();

    expect(launched, Uri.parse(url));
    expect(result, isTrue);
  });

  testWidgets('取消 HTTP 风险提示时不打开链接', (tester) async {
    var launchCount = 0;
    bool? result = true;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await launchExternalWebLink(
              context,
              Uri.parse('http://example.com'),
              launcher: (_) async {
                launchCount++;
                return true;
              },
            );
          },
          child: const Text('打开'),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(launchCount, 0);
    expect(result, isNull);
  });
}
