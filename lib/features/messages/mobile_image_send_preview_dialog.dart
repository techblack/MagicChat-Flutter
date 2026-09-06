import 'dart:typed_data';

import 'package:flutter/material.dart';

class MobileImageSendPreviewResult {
  const MobileImageSendPreviewResult({this.caption = ''});

  final String caption;
}

class MobileImageSendPreviewItem {
  const MobileImageSendPreviewItem({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

Future<MobileImageSendPreviewResult?> showMobileImageSendPreviewDialog(
  BuildContext context, {
  required List<MobileImageSendPreviewItem> images,
}) =>
    showDialog<MobileImageSendPreviewResult>(
      context: context,
      builder: (_) => _MobileImageSendPreviewDialog(images: images),
    );

class _MobileImageSendPreviewDialog extends StatefulWidget {
  const _MobileImageSendPreviewDialog({
    required this.images,
  });

  final List<MobileImageSendPreviewItem> images;

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
  Widget build(BuildContext context) {
    final images = widget.images;
    final totalBytes =
        images.fold<int>(0, (total, item) => total + item.bytes.length);
    return AlertDialog(
      title: Text(images.length == 1 ? '发送图片' : '发送 ${images.length} 张图片'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (images.length == 1)
                _preview(images.single, height: 360)
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: images.length,
                  itemBuilder: (_, index) => _preview(
                    images[index],
                    index: index,
                    height: 120,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                images.length == 1
                    ? '${images.single.fileName} · ${_formatSize(totalBytes)}'
                    : '共 ${images.length} 张 · ${_formatSize(totalBytes)}',
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
                decoration: InputDecoration(
                  labelText: images.length == 1 ? '图片说明（可选）' : '图片说明（附在第一张，可选）',
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
  }

  Widget _preview(MobileImageSendPreviewItem item,
          {int? index, required double height}) =>
      Semantics(
        image: true,
        label: index == null ? '待发送图片预览' : '待发送图片 ${index + 1}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(index == null ? 12 : 8),
          child: SizedBox(
            height: height,
            child: Image.memory(item.bytes, fit: BoxFit.contain),
          ),
        ),
      );

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
