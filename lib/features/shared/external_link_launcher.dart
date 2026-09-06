import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

/// 使用系统浏览器打开 HTTP(S) 链接，并在未加密 HTTP 链接前要求确认。
/// 返回 `null` 表示用户取消，`false` 表示地址无效或系统无法打开。
Future<bool?> launchExternalWebLink(
  BuildContext context,
  Uri uri, {
  ExternalUriLauncher? launcher,
}) async {
  final value = uri.toString();
  final scheme = uri.scheme.toLowerCase();
  if (value.length > 4096 ||
      value.contains('\u0000') ||
      (scheme != 'http' && scheme != 'https') ||
      uri.host.isEmpty) {
    return false;
  }
  if (scheme == 'http') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _InsecureHttpLinkDialog(uri: uri),
    );
    if (confirmed != true || !context.mounted) return null;
  }
  try {
    return await (launcher ?? _launchWithSystemBrowser)(uri);
  } catch (_) {
    return false;
  }
}

Future<bool> _launchWithSystemBrowser(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class _InsecureHttpLinkDialog extends StatelessWidget {
  const _InsecureHttpLinkDialog({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: colors.error, size: 32),
      title: const Text('打开不安全的 HTTP 链接？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('该连接未加密，传输内容可能被窃听或篡改。请确认目标地址可信。'),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目标地址 · ${uri.host}',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 6),
                SelectableText(uri.toString(),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('继续打开'),
        ),
      ],
    );
  }
}
