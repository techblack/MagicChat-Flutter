import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

enum CollapsibleMessageVariant { text, markdown }

class CollapsibleMessageContent extends StatefulWidget {
  const CollapsibleMessageContent({
    required this.variant,
    required this.contentIdentity,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.builder,
    super.key,
  });

  final CollapsibleMessageVariant variant;
  final Object contentIdentity;
  final Color backgroundColor;
  final Color foregroundColor;
  final WidgetBuilder builder;

  @override
  State<CollapsibleMessageContent> createState() =>
      _CollapsibleMessageContentState();
}

class _CollapsibleMessageContentState extends State<CollapsibleMessageContent> {
  double? _contentHeight;
  double _collapsedHeight = 0;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant CollapsibleMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentIdentity != widget.contentIdentity ||
        oldWidget.variant != widget.variant) {
      _contentHeight = null;
      _expanded = false;
    }
  }

  void _onContentSize(Size size) {
    if (!mounted ||
        (_contentHeight != null &&
            (_contentHeight! - size.height).abs() < .5)) {
      return;
    }
    setState(() {
      _contentHeight = size.height;
      if (size.height <= _collapsedHeight + 1) _expanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    _collapsedHeight = switch ((widget.variant, wide)) {
      (CollapsibleMessageVariant.text, false) => 192,
      (CollapsibleMessageVariant.text, true) => 273,
      (CollapsibleMessageVariant.markdown, false) => 240,
      (CollapsibleMessageVariant.markdown, true) => 360,
    };
    return LayoutBuilder(builder: (context, constraints) {
      final height = _contentHeight;
      final canExpand = height != null && height > _collapsedHeight + 1;
      final expanded = canExpand && _expanded;
      const toggleHeight = 30.0;
      final visibleContentHeight = canExpand && !expanded
          ? _collapsedHeight - toggleHeight
          : _collapsedHeight;
      final measuredContent = _MeasuredClippedMessageContent(
        key: ValueKey((widget.variant, widget.contentIdentity)),
        maxHeight: expanded ? double.infinity : visibleContentHeight,
        onSizeChanged: _onContentSize,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: widget.builder(context),
        ),
      );
      final content = canExpand && !expanded
          ? Stack(children: [
              measuredContent,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 52,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          widget.backgroundColor.withValues(alpha: 0),
                          widget.backgroundColor,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ])
          : measuredContent;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            canExpand ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
        children: [
          content,
          if (canExpand)
            SizedBox(
              height: toggleHeight,
              child: TextButton.icon(
                key: const ValueKey('collapsible-message-toggle'),
                onPressed: () => setState(() => _expanded = !expanded),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 17),
                label: Text(expanded ? '收起' : '展开'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.foregroundColor,
                  minimumSize: const Size.fromHeight(toggleHeight),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _MeasuredClippedMessageContent extends SingleChildRenderObjectWidget {
  const _MeasuredClippedMessageContent({
    required this.maxHeight,
    required this.onSizeChanged,
    super.key,
    required super.child,
  });

  final double maxHeight;
  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasuredClippedMessageRenderObject(maxHeight, onSizeChanged);

  @override
  void updateRenderObject(
      BuildContext context, _MeasuredClippedMessageRenderObject renderObject) {
    renderObject
      ..maxHeight = maxHeight
      ..onSizeChanged = onSizeChanged;
  }
}

class _MeasuredClippedMessageRenderObject extends RenderProxyBox {
  _MeasuredClippedMessageRenderObject(this._maxHeight, this.onSizeChanged);

  double _maxHeight;
  ValueChanged<Size> onSizeChanged;
  Size? _reportedSize;

  set maxHeight(double value) {
    if (_maxHeight == value) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    final naturalSize = child.size;
    size = constraints.constrain(Size(
      naturalSize.width,
      naturalSize.height.clamp(0, _maxHeight),
    ));
    if (_reportedSize != naturalSize) {
      _reportedSize = naturalSize;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onSizeChanged(naturalSize));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (child.size.height <= size.height) {
      context.paintChild(child, offset);
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      offset & size,
      (context, offset) => context.paintChild(child, offset),
    );
  }
}
