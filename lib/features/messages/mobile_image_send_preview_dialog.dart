import 'dart:typed_data';

import 'package:flutter/material.dart';

class MobileImageSendPreviewResult {
  const MobileImageSendPreviewResult({this.caption = ''});

  final String caption;
}

Future<MobileImageSendPreviewResult?> showMobileImageSendPreviewDialog(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
}) =>
    showDialog<MobileImageSendPreviewResult>(
      context: context,
      builder: (_) => _MobileImageSendPreviewDialog(
        bytes: bytes,
        fileName: fileName,
      ),
    );

class _MobileImageSendPreviewDialog extends StatefulWidget {
  const _MobileImageSendPreviewDialog({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;

  @override
  State<_MobileImageSendPreviewDialog> createState() =>
      _MobileImageSendPreviewDialogState();
}

class _MobileImageSendPreviewDialogState
    extends State<_MobileImageSendPreviewDialog> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('发送图片'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  image: true,
                  label: '待发送图片预览',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: Image.memory(widget.bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.fileName} · ${_formatSize(widget.bytes.length)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _caption,
                  maxLength: 1000,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '图片说明（可选）',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              MobileImageSendPreviewResult(caption: _caption.text.trim()),
            ),
            icon: const Icon(Icons.send_outlined),
            label: const Text('发送'),
          ),
        ],
      );

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
