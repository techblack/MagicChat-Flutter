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
      final measuredContent = _MessageContentSizeReporter(
        onSizeChanged: _onContentSize,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: widget.builder(context),
        ),
      );
      final content = canExpand && !expanded
          ? SizedBox(
              height: _collapsedHeight,
              child: Stack(children: [
                Positioned.fill(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: constraints.maxWidth,
                      maxWidth: constraints.maxWidth,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: measuredContent,
                    ),
                  ),
                ),
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
              ]),
            )
          : measuredContent;
      return AnimatedSize(
        key: ValueKey(height != null),
        // 使用极短过渡避免首帧测量触发零时长 AnimatedSize 的布局重入，
        // 同时不会在 Android 手势滚动时产生可感知的回弹动画。
        duration: const Duration(milliseconds: 1),
        reverseDuration: const Duration(milliseconds: 1),
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              canExpand ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            content,
            if (canExpand)
              TextButton.icon(
                key: const ValueKey('collapsible-message-toggle'),
                onPressed: () => setState(() => _expanded = !expanded),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 17),
                label: Text(expanded ? '收起' : '展开'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.foregroundColor,
                  minimumSize: const Size.fromHeight(30),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _MessageContentSizeReporter extends SingleChildRenderObjectWidget {
  const _MessageContentSizeReporter({
    required this.onSizeChanged,
    required super.child,
  });

  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MessageContentSizeRenderObject(onSizeChanged);

  @override
  void updateRenderObject(
      BuildContext context, _MessageContentSizeRenderObject renderObject) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _MessageContentSizeRenderObject extends RenderProxyBox {
  _MessageContentSizeRenderObject(this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _reportedSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_reportedSize == size) return;
    final measuredSize = size;
    _reportedSize = measuredSize;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => onSizeChanged(measuredSize));
  }
}
