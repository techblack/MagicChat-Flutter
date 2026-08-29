import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/main.dart';

void main() {
  testWidgets('饼图消息显示标题、图例和描述', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChartPreview(
          body: const {
            'type': 'chart',
            'chart_type': 'pie',
            'title': '客户端平台分布',
            'description': '按活跃设备统计',
            'data': {
              'items': [
                {'name': 'Android', 'value': 70},
                {'name': 'iOS', 'value': 30},
              ],
            },
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('客户端平台分布'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('按活跃设备统计'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('evidence/message_chart_pie.png'),
    );
  });
}
