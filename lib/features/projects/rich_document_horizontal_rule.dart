import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/document_collaboration.dart';

typedef RichDocumentHorizontalRuleDialogResult = ({
  RichDocumentHorizontalRuleAttributes attributes,
  bool deleted,
});

class RichDocumentHorizontalRuleView extends StatelessWidget {
  const RichDocumentHorizontalRuleView({
    required this.attributes,
    this.onTap,
    super.key,
  });

  final RichDocumentHorizontalRuleAttributes attributes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: onTap == null ? '分割线' : '设置分割线',
        child: InkWell(
          key: const ValueKey('rich-document-horizontal-rule'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CustomPaint(
                key: const ValueKey('rich-document-horizontal-rule-line'),
                painter: _HorizontalRulePainter(
                  attributes: attributes,
                  color: Theme.of(context).colorScheme.outline,
                ),
                size: const Size(double.infinity, 32),
              ),
            ),
          ),
        ),
      );
}

class RichDocumentHorizontalRuleDialog extends StatefulWidget {
  const RichDocumentHorizontalRuleDialog({
    required this.initialValue,
    super.key,
  });

  final RichDocumentHorizontalRuleAttributes initialValue;

  @override
  State<RichDocumentHorizontalRuleDialog> createState() =>
      _RichDocumentHorizontalRuleDialogState();
}

class _RichDocumentHorizontalRuleDialogState
    extends State<RichDocumentHorizontalRuleDialog> {
  late String _lineStyle = widget.initialValue.lineStyle;
  late int _thickness = widget.initialValue.thickness;

  void _setLineStyle(String? value) {
    if (value == null) return;
    setState(() {
      _lineStyle = value;
      if (value == 'double' && _thickness < 3) _thickness = 3;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('设置分割线'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RichDocumentHorizontalRuleView(
                attributes: (lineStyle: _lineStyle, thickness: _thickness),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('rich-horizontal-rule-style'),
                initialValue: _lineStyle,
                decoration: const InputDecoration(labelText: '分割线样式'),
                items: const [
                  DropdownMenuItem(value: 'solid', child: Text('实线')),
                  DropdownMenuItem(value: 'dashed', child: Text('虚线')),
                  DropdownMenuItem(value: 'dotted', child: Text('点线')),
                  DropdownMenuItem(value: 'double', child: Text('双线')),
                ],
                onChanged: _setLineStyle,
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('粗细'),
                Expanded(
                  child: Slider(
                    key: const ValueKey('rich-horizontal-rule-thickness'),
                    min: 1,
                    max: 6,
                    divisions: 5,
                    value: _thickness.toDouble(),
                    label: '$_thickness px',
                    onChanged: (value) =>
                        setState(() => _thickness = value.round()),
                  ),
                ),
                SizedBox(width: 42, child: Text('$_thickness px')),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Navigator.pop<RichDocumentHorizontalRuleDialogResult>(
              context,
              (
                attributes: (
                  lineStyle: _lineStyle,
                  thickness: _thickness,
                ),
                deleted: true,
              ),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop<RichDocumentHorizontalRuleDialogResult>(
              context,
              (
                attributes: (
                  lineStyle: _lineStyle,
                  thickness: _thickness,
                ),
                deleted: false,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      );
}

class _HorizontalRulePainter extends CustomPainter {
  const _HorizontalRulePainter({
    required this.attributes,
    required this.color,
  });

  final RichDocumentHorizontalRuleAttributes attributes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = attributes.thickness.toDouble()
      ..style = PaintingStyle.stroke;
    if (attributes.lineStyle == 'double') {
      final stroke = math.max(1.0, attributes.thickness / 3);
      final gap = math.max(2.0, stroke * 2);
      paint.strokeWidth = stroke;
      canvas.drawLine(Offset(0, center - gap / 2),
          Offset(size.width, center - gap / 2), paint);
      canvas.drawLine(Offset(0, center + gap / 2),
          Offset(size.width, center + gap / 2), paint);
      return;
    }
    if (attributes.lineStyle == 'solid') {
      canvas.drawLine(Offset(0, center), Offset(size.width, center), paint);
      return;
    }
    final dotted = attributes.lineStyle == 'dotted';
    final segment = dotted ? paint.strokeWidth : 10.0;
    final gap = dotted ? math.max(4.0, paint.strokeWidth * 2) : 6.0;
    paint.strokeCap = dotted ? StrokeCap.round : StrokeCap.butt;
    for (var x = 0.0; x < size.width; x += segment + gap) {
      canvas.drawLine(
        Offset(x, center),
        Offset(math.min(x + segment, size.width), center),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HorizontalRulePainter oldDelegate) =>
      oldDelegate.attributes != attributes || oldDelegate.color != color;
}
