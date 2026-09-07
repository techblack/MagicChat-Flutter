import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

import '../../data/avatar_processor.dart';
import 'user_facing_error.dart';

class AvatarPickerImage {
  const AvatarPickerImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

typedef AvatarImagePicker = Future<AvatarPickerImage?> Function();

Future<AvatarPickerImage?> pickAvatarImage() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    withData: true,
  );
  final file = result?.files.single;
  if (file == null) return null;
  final bytes = file.bytes;
  if (bytes == null) throw const FormatException('无法读取所选图片');
  return AvatarPickerImage(name: file.name, bytes: bytes);
}

class CustomAvatarPicker extends StatefulWidget {
  const CustomAvatarPicker({
    required this.imagePicker,
    required this.saving,
    required this.onSourceChanged,
    required this.onSave,
    required this.keyPrefix,
    super.key,
  });

  final AvatarImagePicker imagePicker;
  final bool saving;
  final VoidCallback onSourceChanged;
  final Future<void> Function(Uint8List bytes) onSave;
  final String keyPrefix;

  @override
  State<CustomAvatarPicker> createState() => _CustomAvatarPickerState();
}

class _CustomAvatarPickerState extends State<CustomAvatarPicker> {
  static const _maxSourceBytes = 5 * 1024 * 1024;
  AvatarPickerImage? _source;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  double _zoom = 1;
  double _focusX = 0.5;
  double _focusY = 0.5;
  String _error = '';

  ValueKey<String> _key(String name) => ValueKey('${widget.keyPrefix}-$name');

  Future<void> _pick() async {
    try {
      final source = await widget.imagePicker();
      if (source == null || !mounted) return;
      if (source.bytes.length > _maxSourceBytes) {
        throw const FormatException('图片文件不能超过 5MiB');
      }
      final decoded = image.decodeImage(source.bytes);
      if (decoded == null) throw const FormatException('图片读取失败');
      if (decoded.width < 64 || decoded.height < 64) {
        throw const FormatException('图片尺寸不能小于 64×64');
      }
      if (decoded.width > 4096 || decoded.height > 4096) {
        throw const FormatException('图片尺寸不能超过 4096×4096');
      }
      setState(() {
        _source = source;
        _sourceWidth = decoded.width;
        _sourceHeight = decoded.height;
        _zoom = 1;
        _focusX = 0.5;
        _focusY = 0.5;
        _error = '';
      });
      widget.onSourceChanged();
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    }
  }

  double _clampFocus(double value, int sourceExtent) {
    final cropSize = math.min(_sourceWidth, _sourceHeight) / _zoom;
    final halfVisible = cropSize / sourceExtent / 2;
    return value.clamp(halfVisible, 1 - halfVisible);
  }

  void _moveFocus(
    DragUpdateDetails details,
    double displayWidth,
    double displayHeight,
  ) {
    setState(() {
      _focusX = _clampFocus(
        _focusX - details.delta.dx / displayWidth,
        _sourceWidth,
      );
      _focusY = _clampFocus(
        _focusY - details.delta.dy / displayHeight,
        _sourceHeight,
      );
    });
  }

  Future<void> _save() async {
    final source = _source;
    if (source == null || widget.saving) return;
    final bytes = const AvatarProcessor().process(
      source.bytes,
      zoom: _zoom,
      focusX: _focusX,
      focusY: _focusY,
    );
    await widget.onSave(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source == null)
          AspectRatio(
            aspectRatio: 1,
            child: OutlinedButton(
              key: _key('pick'),
              onPressed: widget.saving ? null : _pick,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file_outlined, size: 40),
                  SizedBox(height: 12),
                  Text('选择图片'),
                  SizedBox(height: 4),
                  Text('PNG、JPG、WebP，最大 5MiB'),
                ],
              ),
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 280.0);
              final baseScale = math.max(
                size / _sourceWidth,
                size / _sourceHeight,
              );
              final displayWidth = _sourceWidth * baseScale * _zoom;
              final displayHeight = _sourceHeight * baseScale * _zoom;
              final focusX = _clampFocus(_focusX, _sourceWidth);
              final focusY = _clampFocus(_focusY, _sourceHeight);
              return Align(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    key: _key('crop'),
                    onPanUpdate: widget.saving
                        ? null
                        : (details) =>
                            _moveFocus(details, displayWidth, displayHeight),
                    child: SizedBox.square(
                      dimension: size,
                      child: Stack(
                        children: [
                          Positioned(
                            left: size / 2 - focusX * displayWidth,
                            top: size / 2 - focusY * displayHeight,
                            width: displayWidth,
                            height: displayHeight,
                            child: Image.memory(
                              source.bytes,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.zoom_out),
              Expanded(
                child: Slider(
                  key: _key('zoom'),
                  value: _zoom,
                  min: 1,
                  max: 3,
                  divisions: 20,
                  label: '${_zoom.toStringAsFixed(1)}×',
                  onChanged: widget.saving
                      ? null
                      : (value) => setState(() {
                            _zoom = value;
                            _focusX = _clampFocus(_focusX, _sourceWidth);
                            _focusY = _clampFocus(_focusY, _sourceHeight);
                          }),
                ),
              ),
              const Icon(Icons.zoom_in),
            ],
          ),
          Text(
            '拖动图片调整裁剪位置',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: _key('repick'),
                onPressed: widget.saving ? null : _pick,
                icon: const Icon(Icons.refresh),
                label: const Text('重新选择'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: _key('save'),
                onPressed: widget.saving ? null : _save,
                child: widget.saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _error,
            key: _key('error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
