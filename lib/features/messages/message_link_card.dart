import 'package:flutter/material.dart';

import '../../domain/message_content.dart';

/// 链接和卡片消息的统一可读展示。
///
/// 外链只有通过 [parseExternalWebUri] 校验的 HTTP(S) 地址才会启用点击回调；
/// 卡片内部路径需显式设置 [allowInternalPath] 和 [onOpenInternal]。
/// 无效地址仍然保留正文，避免历史消息因数据异常而消失。
class MessageLinkCard extends StatelessWidget {
  const MessageLinkCard({
    required this.title,
    required this.description,
    required this.url,
    this.icon = Icons.link_outlined,
    this.onOpen,
    this.allowInternalPath = false,
    this.onOpenInternal,
    this.textColor,
    this.accentColor,
    this.backgroundColor,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final String description;
  final String url;
  final IconData icon;
  final ValueChanged<Uri>? onOpen;
  final bool allowInternalPath;
  final ValueChanged<String>? onOpenInternal;
  final Color? textColor;
  final Color? accentColor;
  final Color? backgroundColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final target = parseExternalWebUri(url);
    final internalTarget =
        allowInternalPath ? parseInternalMessagePath(url) : null;
    final interactive = (target != null && onOpen != null) ||
        (internalTarget != null && onOpenInternal != null);
    final foreground = textColor ?? colors.onSurface;
    final accent = accentColor ?? colors.primary;
    final visibleTitle = title.trim().isEmpty ? '链接' : title.trim();
    final visibleDescription = description.trim();
    final label = semanticLabel ?? visibleTitle;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Semantics(
        container: true,
        button: interactive,
        enabled: interactive,
        label: label,
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: backgroundColor ?? colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side:
                BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: interactive
                ? () {
                    if (target != null && onOpen != null) {
                      onOpen!(target);
                    } else if (internalTarget != null &&
                        onOpenInternal != null) {
                      onOpenInternal!(internalTarget);
                    }
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 19, color: accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          visibleTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (visibleDescription.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      visibleDescription,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: foreground.withValues(alpha: .78),
                            height: 1.35,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
