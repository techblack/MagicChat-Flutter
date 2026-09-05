import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/features/projects/rich_table_size_picker.dart';

void main() {
  testWidgets('表格尺寸选择器预览并返回所选行列', (tester) async {
    RichTableSize? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              selected = await showDialog<RichTableSize>(
                  context: context,
                  builder: (_) => const RichTableSizePicker());
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('3 × 3'), findsOneWidget);

    final cell = find.byKey(const ValueKey('rich-table-size-4-5'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(cell));
    await tester.pump();
    expect(find.text('4 × 5'), findsOneWidget);
    await gesture.removePointer();
    await tester.tap(cell);
    await tester.pumpAndSettle();

    expect(selected, (rows: 4, columns: 5));
  });
}
