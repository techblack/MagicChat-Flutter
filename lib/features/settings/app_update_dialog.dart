import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/update_installer.dart';
import '../../data/update_service.dart';

typedef UpdateDownloadPageLauncher = Future<bool> Function(Uri uri);

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    required this.release,
    required this.installer,
    this.openDownloadPage,
    super.key,
  });

  final AppRelease release;
  final UpdateInstaller installer;
  final UpdateDownloadPageLauncher? openDownloadPage;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await widget.installer.downloadAndInstall(
        widget.release,
        onProgress: (value) {
          final next = value.clamp(0, 1).toDouble();
          if (mounted && (next == 1 || next - _progress >= .01)) {
            setState(() => _progress = next);
          }
        },
      );
      if (mounted) Navigator.pop(context);
    } on UpdateDownloadCancelled {
      if (mounted) setState(() => _downloading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _cancelDownload() async {
    await widget.installer.cancel();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openDownloadPage() async {
    try {
      final launcher = widget.openDownloadPage ?? _launchDownloadPage;
      if (!await launcher(Uri.parse(widget.release.url))) {
        throw Exception('无法打开下载页');
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  void dispose() {
    if (_downloading) unawaited(widget.installer.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final percent = (_progress * 100).round();
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        icon: Icon(Icons.system_update_alt, color: colors.primary, size: 32),
        title: Text(_downloading ? '正在更新' : '发现新版本'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'MagicChat ${widget.release.version}（${widget.release.build}）'),
              if (_downloading) ...[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.installer.progressLabel),
                    Text('$percent%',
                        style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 8),
                Text(widget.installer.completionHint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
        ),
        actions: _downloading
            ? [
                TextButton(
                    onPressed: _cancelDownload, child: const Text('取消下载')),
              ]
            : [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('稍后')),
                FilledButton.icon(
                  onPressed: widget.installer.supported
                      ? _startUpdate
                      : _openDownloadPage,
                  icon: Icon(widget.installer.supported
                      ? Icons.download
                      : Icons.open_in_new),
                  label: Text(widget.installer.supported ? '下载安装' : '打开下载页'),
                ),
              ],
      ),
    );
  }
}

Future<bool> _launchDownloadPage(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
