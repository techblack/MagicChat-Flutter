part of '../../main.dart';

class _ChoiceOptionView {
  const _ChoiceOptionView({required this.id, required this.label});

  final String id;
  final String label;
}

List<_ChoiceOptionView> _choiceOptions(Object? value) => value is List
    ? value
        .whereType<Map<String, dynamic>>()
        .map((option) {
          final id = option['id'];
          final label = option['label'] ?? option['text'];
          return id is String && id.isNotEmpty && label is String
              ? _ChoiceOptionView(id: id, label: label)
              : null;
        })
        .whereType<_ChoiceOptionView>()
        .toList(growable: false)
    : const [];

class _ChoiceOptions extends StatefulWidget {
  const _ChoiceOptions(
      {required this.options,
      required this.selection,
      required this.choice,
      required this.canRespond,
      required this.onSubmit});

  final List<_ChoiceOptionView> options;
  final String selection;
  final MessageChoiceState? choice;
  final bool canRespond;
  final Future<void> Function(List<String> optionIds) onSubmit;

  @override
  State<_ChoiceOptions> createState() => _ChoiceOptionsState();
}

class _ChoiceOptionsState extends State<_ChoiceOptions> {
  late Set<String> _selected;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _selected = {...?widget.choice?.myOptionIds};
  }

  @override
  void didUpdateWidget(covariant _ChoiceOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_submitting && widget.choice != oldWidget.choice) {
      _selected = {...?widget.choice?.myOptionIds};
    }
  }

  Future<void> _submit(List<String> ids) async {
    if (ids.isEmpty || _submitting || _submitted || !widget.canRespond) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(ids);
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('提交选择失败：${userFacingError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answered =
        _submitted || widget.choice?.myOptionIds.isNotEmpty == true;
    final counts = {
      for (final option in widget.choice?.options ?? const [])
        option.id: option.responseCount
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...widget.options.map((option) {
        final count = counts[option.id] ?? 0;
        final label = count > 0 ? '${option.label} · $count' : option.label;
        final selected = _selected.contains(option.id);
        return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: widget.selection == 'multiple'
                ? FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: !answered && widget.canRespond && !_submitting
                        ? (value) => setState(() {
                              if (value) {
                                _selected.add(option.id);
                              } else {
                                _selected.remove(option.id);
                              }
                            })
                        : null)
                : ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: !answered && widget.canRespond && !_submitting
                        ? (_) => _submit([option.id])
                        : null));
      }),
      if (widget.selection == 'multiple')
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: !answered && !_submitting && widget.canRespond
                    ? () => _submit(_selected.toList())
                    : null,
                child: Text(_submitting
                    ? '提交中…'
                    : answered
                        ? '已提交'
                        : '提交选择'))),
      if (widget.choice != null)
        Text('${widget.choice!.responseCount} 人已选择',
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _ForwardBundlePreview extends StatelessWidget {
  const _ForwardBundlePreview(
      {required this.body,
      required this.summary,
      this.contactsFuture,
      this.textColor});

  final Map<String, dynamic> body;
  final String summary;
  final Future<List<Contact>>? contactsFuture;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final items = body['items'];
    final first = items is List && items.isNotEmpty && items.first is Map
        ? (items.first as Map)['summary']
        : null;
    final preview =
        first is String && first.trim().isNotEmpty ? first.trim() : summary;
    return FutureBuilder<List<Contact>>(
      future: contactsFuture,
      builder: (context, snapshot) {
        final text = formatMentionText(
            preview,
            (snapshot.data ?? const <Contact>[]).map((contact) => (
                  id: contact.id,
                  name: contact.displayName,
                )));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.forum_outlined, color: textColor, size: 18),
              const SizedBox(width: 6),
              Text('聊天记录',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.w600)),
            ]),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor)),
              ),
          ],
        );
      },
    );
  }
}

/// 结构化图表消息的轻量级跨平台预览。
class ChartPreview extends StatelessWidget {
  const ChartPreview({required this.body, super.key});
  final Map<String, dynamic> body;

  @override
  Widget build(BuildContext context) {
    final data = body['data'];
    if (data is! Map<String, dynamic>) return const SizedBox.shrink();
    final chart = switch (body['chart_type']) {
      'line' => _ChartLine(data: data),
      'radar' => _ChartRadar(data: data),
      'pie' => _ChartPie(data: data),
      _ => _cartesianChart(data),
    };
    final title = body['title'];
    final description = body['description'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title is String && title.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(title.trim(),
                style: Theme.of(context).textTheme.titleSmall),
          ),
        chart,
        if (description is String && description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(description.trim(),
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _cartesianChart(Map<String, dynamic> data) {
    final labels = data['labels'];
    final series = data['series'];
    if (labels is! List || series is! List || labels.isEmpty) {
      final items = data['items'];
      return items is List ? _ChartBars(items: items) : const SizedBox.shrink();
    }
    final typedSeries = series.whereType<Map<String, dynamic>>().toList();
    final first = typedSeries.isEmpty ? null : typedSeries.first;
    final values = first?['values'];
    if (values is! List) return const SizedBox.shrink();
    return _ChartBars(items: [
      for (var i = 0; i < labels.length && i < values.length; i++)
        {'name': '${labels[i]}', 'value': values[i]}
    ]);
  }
}

class _ChartPie extends StatelessWidget {
  const _ChartPie({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rawItems = data['items'];
    if (rawItems is! List) return const SizedBox.shrink();
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map((item) => (
              name: '${item['name'] ?? item['label'] ?? ''}',
              value: (item['value'] as num?)?.toDouble() ?? 0,
            ))
        .where((item) => item.name.trim().isNotEmpty && item.value > 0)
        .toList(growable: false);
    final total = items.fold<double>(0, (sum, item) => sum + item.value);
    if (items.length < 2 || total <= 0) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
            width: 160,
            height: 160,
            child: CustomPaint(
                painter: _PieChartPainter(
                    items.map((item) => item.value).toList()))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _PieChartPainter
                                .palette[i % _PieChartPainter.palette.length])),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(items[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(_formatChartNumber(items[i].value)),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter(this.values);
  final List<double> values;
  static const palette = [
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.purple,
    Colors.red,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final diameter = min(size.width, size.height) - 8;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: diameter,
        height: diameter);
    var start = -pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * pi;
      canvas.drawArc(rect, start, sweep, true,
          Paint()..color = palette[i % palette.length]);
      start += sweep;
    }
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), diameter * .22,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

String _formatChartNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _formatAttachmentSize(num value) {
  final bytes = value < 0 ? 0 : value.toDouble();
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _ChartLine extends StatelessWidget {
  const _ChartLine({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final labels = data['labels'];
    final series = data['series'];
    if (labels is! List || series is! List || labels.length < 2) {
      return const SizedBox.shrink();
    }
    final values = series
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final raw = item['values'];
          return raw is List
              ? raw.map((value) => (value as num?)?.toDouble()).toList()
              : <double?>[];
        })
        .where((values) => values.length >= labels.length)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: CustomPaint(painter: _LineChartPainter(values)),
    );
  }
}

class _ChartRadar extends StatelessWidget {
  const _ChartRadar({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final axes = data['axes'];
    final series = data['series'];
    if (axes is! List || axes.length < 3 || series is! List) {
      return const SizedBox.shrink();
    }
    final maxes = axes
        .whereType<Map<String, dynamic>>()
        .map((axis) => (axis['max'] as num?)?.toDouble() ?? 1)
        .toList();
    final values = series
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final raw = item['values'];
          return raw is List
              ? raw.map((value) => (value as num?)?.toDouble() ?? 0).toList()
              : <double>[];
        })
        .where((item) => item.length == maxes.length)
        .toList();
    if (maxes.length != axes.length || values.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
        height: 220,
        width: double.infinity,
        child: CustomPaint(painter: _RadarChartPainter(maxes, values)));
  }
}

class _RadarChartPainter extends CustomPainter {
  _RadarChartPainter(this.maxes, this.series);
  final List<double> maxes;
  final List<List<double>> series;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .38;
    final count = maxes.length;
    Offset point(double r, int index) {
      final angle =
          -3.141592653589793 / 2 + index * 2 * 3.141592653589793 / count;
      return center + Offset(r * cos(angle), r * sin(angle));
    }

    final grid = Paint()
      ..color = const Color(0x44333333)
      ..style = PaintingStyle.stroke;
    for (var level = 1; level <= 4; level++) {
      final path = Path()
        ..moveTo(
            point(radius * level / 4, 0).dx, point(radius * level / 4, 0).dy);
      for (var i = 1; i < count; i++) {
        final p = point(radius * level / 4, i);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    for (var i = 0; i < count; i++)
      canvas.drawLine(center, point(radius, i), grid);
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple];
    for (var s = 0; s < series.length; s++) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final p = point(radius * (series[s][i] / maxes[i]).clamp(0, 1), i);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      final color = colors[s % colors.length];
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .18));
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) => true;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.series);
  final List<List<double?>> series;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final values = series.expand((item) => item).whereType<double>().toList();
    if (values.isEmpty) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max == min ? 1 : max - min;
    final grid = Paint()
      ..color = const Color(0x33222222)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple];
    for (var s = 0; s < series.length; s++) {
      final points = <Offset>[];
      final item = series[s];
      for (var i = 0; i < item.length; i++) {
        final value = item[i];
        if (value == null) continue;
        points.add(Offset(plot.left + plot.width * i / (item.length - 1),
            plot.bottom - (value - min) / range * plot.height));
      }
      if (points.length < 2) continue;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) path.lineTo(point.dx, point.dy);
      canvas.drawPath(
          path,
          Paint()
            ..color = colors[s % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.series != series;
}

class _ChartBars extends StatelessWidget {
  const _ChartBars({required this.items});
  final List<Object?> items;

  @override
  Widget build(BuildContext context) {
    final values = items.map((item) {
      if (item is Map<String, dynamic>)
        return (item['value'] as num?)?.toDouble() ?? 0;
      return 0.0;
    }).toList();
    final max = values.fold<double>(
        0, (current, value) => value > current ? value : current);
    if (max <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                  width: 90,
                  child:
                      Text(_label(items[i]), overflow: TextOverflow.ellipsis)),
              Expanded(
                  child: LinearProgressIndicator(
                      value: values[i] / max, minHeight: 10)),
              const SizedBox(width: 8),
              Text(_format(values[i]))
            ]),
          )
      ],
    );
  }

  String _label(Object? item) => item is Map<String, dynamic>
      ? '${item['name'] ?? item['label'] ?? ''}'
      : '';
  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}
