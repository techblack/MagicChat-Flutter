import 'package:flutter/material.dart';

class ConversationAnnouncement extends StatefulWidget {
  const ConversationAnnouncement({required this.announcement, super.key});

  final String announcement;

  @override
  State<ConversationAnnouncement> createState() =>
      _ConversationAnnouncementState();
}

class _ConversationAnnouncementState extends State<ConversationAnnouncement> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ConversationAnnouncement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement != widget.announcement) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.announcement.trim();
    if (content.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(height: 1.45) ??
        const TextStyle(fontSize: 12, height: 1.45);
    return LayoutBuilder(builder: (context, constraints) {
      // 展开按钮位于正文下方，不再与大字号的第三行争用横向空间。
      final textWidth =
          (constraints.maxWidth - 48).clamp(1.0, double.infinity).toDouble();
      final painter = TextPainter(
        text: TextSpan(text: content, style: style),
        maxLines: 3,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: textWidth);
      final canExpand = painter.didExceedMaxLines;
      final expanded = canExpand && _expanded;
      return Semantics(
        container: true,
        label: '群公告',
        child: Material(
          key: const ValueKey('conversation-announcement'),
          color: theme.colorScheme.surfaceContainerLow,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.campaign_outlined,
                      size: 18, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        content,
                        key: const ValueKey('conversation-announcement-text'),
                        maxLines: expanded ? null : 3,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: style,
                      ),
                      if (canExpand)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const ValueKey(
                                'conversation-announcement-toggle'),
                            onPressed: () =>
                                setState(() => _expanded = !expanded),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 28),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(expanded ? '收起' : '展开'),
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}
