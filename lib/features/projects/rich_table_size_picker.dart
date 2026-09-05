import 'package:flutter/material.dart';

typedef RichTableSize = ({int rows, int columns});

class RichTableSizePicker extends StatefulWidget {
  const RichTableSizePicker({super.key});

  @override
  State<RichTableSizePicker> createState() => _RichTableSizePickerState();
}

class _RichTableSizePickerState extends State<RichTableSizePicker> {
  int _rows = 3;
  int _columns = 3;

  void _preview(int rows, int columns) {
    if (_rows != rows || _columns != columns) {
      setState(() {
        _rows = rows;
        _columns = columns;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('插入表格')),
        Text('$_rows × $_columns',
            key: const ValueKey('rich-table-size-label'),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: colors.primary)),
      ]),
      content: SizedBox(
        width: 280,
        height: 280,
        child: GridView.builder(
          itemCount: 100,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10, mainAxisSpacing: 3, crossAxisSpacing: 3),
          itemBuilder: (context, index) {
            final rows = index ~/ 10 + 1;
            final columns = index % 10 + 1;
            final selected = rows <= _rows && columns <= _columns;
            return Semantics(
              button: true,
              label: '$rows 行 $columns 列',
              child: MouseRegion(
                onEnter: (_) => _preview(rows, columns),
                child: InkWell(
                  key: ValueKey('rich-table-size-$rows-$columns'),
                  onTap: () =>
                      Navigator.pop(context, (rows: rows, columns: columns)),
                  borderRadius: BorderRadius.circular(4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primaryContainer
                          : colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: selected
                              ? colors.primary
                              : colors.outlineVariant),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }
}
