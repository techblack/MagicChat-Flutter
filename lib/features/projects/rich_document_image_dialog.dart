import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/document_collaboration.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';

typedef RichDocumentImageDialogResult = ({
  bool deleted,
  RichDocumentImageAttributes? attributes,
});

class RichDocumentImageDialog extends StatefulWidget {
  const RichDocumentImageDialog({
    required this.repository,
    required this.initialValue,
    super.key,
  });

  final MagicChatRepository repository;
  final RichDocumentImageAttributes initialValue;

  @override
  State<RichDocumentImageDialog> createState() =>
      _RichDocumentImageDialogState();
}

class _RichDocumentImageDialogState extends State<RichDocumentImageDialog> {
  late final TextEditingController _url =
      TextEditingController(text: widget.initialValue.externalUrl ?? '');
  late final TextEditingController _alt =
      TextEditingController(text: widget.initialValue.alt);
  late String _alignment = widget.initialValue.alignment;
  late double _width = widget.initialValue.width.toDouble();
  late String? _fileId = widget.initialValue.fileId;
  Uint8List? _previewBytes;
  bool _uploading = false;

  @override
  void dispose() {
    _url.dispose();
    _alt.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['avif', 'gif', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    if (!mounted || file == null) return;
    if (file.size <= 0 || file.bytes == null) {
      _showError('图片内容为空或无法读取');
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      _showError('图片不能超过 10MiB');
      return;
    }
    final mimeType = _imageMimeType(file.extension);
    if (mimeType == null) {
      _showError('请选择 PNG、JPEG、WebP、GIF 或 AVIF 图片');
      return;
    }
    setState(() => _uploading = true);
    try {
      final uploaded = await widget.repository.uploadTemporaryFile(
          AttachmentUpload(
              path: '',
              name: file.name,
              mimeType: mimeType,
              bytes: file.bytes));
      if (!mounted) return;
      setState(() {
        _fileId = uploaded.id;
        _previewBytes = file.bytes;
        _url.clear();
        if (_alt.text.trim().isEmpty) _alt.text = file.name;
      });
    } catch (error) {
      if (mounted) _showError('上传图片失败：$error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _apply() {
    final input = _url.text.trim();
    final uri = input.isEmpty ? null : Uri.tryParse(input);
    if (input.isNotEmpty &&
        (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
      _showError('在线图片地址必须使用 HTTPS');
      return;
    }
    Navigator.pop<RichDocumentImageDialogResult>(context, (
      deleted: false,
      attributes: (
        alignment: _alignment,
        alt: _alt.text.trim(),
        externalUrl: uri?.toString(),
        fileId: uri == null ? _fileId : null,
        width: _width.round(),
      ),
    ));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('设置图片'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                // 在窄窗口中为对齐和地址输入保留可见空间，避免设置面板
                // 首次打开时只能看到预览而无法直接操作布局选项。
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12)),
                child: _preview(),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'left',
                      icon: Icon(Icons.format_align_left),
                      label: Text('左')),
                  ButtonSegment(
                      value: 'center',
                      icon: Icon(Icons.format_align_center),
                      label: Text('中')),
                  ButtonSegment(
                      value: 'right',
                      icon: Icon(Icons.format_align_right),
                      label: Text('右')),
                ],
                selected: {_alignment},
                onSelectionChanged: _uploading
                    ? null
                    : (value) => setState(() => _alignment = value.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('宽度'),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 20,
                    max: 100,
                    divisions: 16,
                    label: '${_width.round()}%',
                    onChanged: _uploading
                        ? null
                        : (value) => setState(() => _width = value),
                  ),
                ),
                SizedBox(width: 44, child: Text('${_width.round()}%')),
              ]),
              TextField(
                controller: _url,
                enabled: !_uploading,
                onChanged: (_) => setState(() => _previewBytes = null),
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: '在线图片',
                    hintText: 'https://example.com/image.png',
                    prefixIcon: Icon(Icons.link)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _alt,
                enabled: !_uploading,
                maxLength: 500,
                decoration: const InputDecoration(
                    labelText: '图片替代文本',
                    prefixIcon: Icon(Icons.closed_caption_outlined)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload),
              label: Text(_uploading ? '上传中…' : '上传图片')),
          TextButton(
              onPressed: _uploading
                  ? null
                  : () => Navigator.pop<RichDocumentImageDialogResult>(
                      context, (deleted: true, attributes: null)),
              child: Text('删除图片',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
          TextButton(
              onPressed: _uploading ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: _uploading ? null : _apply, child: const Text('应用')),
        ],
      );

  Widget _preview() {
    if (_previewBytes case final bytes?) {
      return Image.memory(bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined));
    }
    final uri = Uri.tryParse(_url.text.trim());
    if (uri?.scheme == 'https' && uri?.host.isNotEmpty == true) {
      return Image.network(uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined));
    }
    if (_fileId != null) {
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.image_outlined, size: 42),
        SizedBox(height: 8),
        Text('图片已上传'),
      ]);
    }
    return const Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.add_photo_alternate_outlined, size: 42),
      SizedBox(height: 8),
      Text('上传图片或填写 HTTPS 地址'),
    ]);
  }
}

String? _imageMimeType(String? extension) => switch (extension?.toLowerCase()) {
      'avif' => 'image/avif',
      'gif' => 'image/gif',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
