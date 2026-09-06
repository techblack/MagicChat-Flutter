import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

import '../../data/avatar_processor.dart';
import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/cached_avatar.dart';
import '../shared/user_facing_error.dart';

const profileBuiltinAvatarCount = 64;

String profileBuiltinAvatarPath(int index) =>
    '/assets/avatars/builtin/${index.toString().padLeft(2, '0')}.webp';

bool isProfileBuiltinAvatar(String value) =>
    RegExp(r'^/assets/avatars/builtin/(0[1-9]|[1-5][0-9]|6[0-4])\.webp$')
        .hasMatch(value);

class ProfileAvatarImage {
  const ProfileAvatarImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

typedef ProfileAvatarImagePicker = Future<ProfileAvatarImage?> Function();

Future<ProfileAvatarImage?> pickProfileAvatarImage() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    withData: true,
  );
  final file = result?.files.single;
  if (file == null) return null;
  final bytes = file.bytes;
  if (bytes == null) throw const FormatException('无法读取所选图片');
  return ProfileAvatarImage(name: file.name, bytes: bytes);
}

class ProfileAvatarPickerDialog extends StatefulWidget {
  const ProfileAvatarPickerDialog({
    required this.repository,
    required this.selectedAvatar,
    required this.onSaveBuiltin,
    required this.onSaveCustom,
    this.serverUrl,
    this.cacheScope,
    this.imagePicker = pickProfileAvatarImage,
    super.key,
  });

  final MagicChatRepository repository;
  final String selectedAvatar;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final Future<CurrentUser> Function(String avatar) onSaveBuiltin;
  final Future<CurrentUser> Function(Uint8List bytes) onSaveCustom;
  final ProfileAvatarImagePicker imagePicker;

  @override
  State<ProfileAvatarPickerDialog> createState() =>
      _ProfileAvatarPickerDialogState();
}

enum _AvatarMode { builtin, custom }

class _ProfileAvatarPickerDialogState extends State<ProfileAvatarPickerDialog> {
  late _AvatarMode _mode;
  late String _draftAvatar;
  bool _saving = false;
  String _saveError = '';

  @override
  void initState() {
    super.initState();
    _draftAvatar = widget.selectedAvatar;
    _mode = isProfileBuiltinAvatar(_draftAvatar)
        ? _AvatarMode.builtin
        : _AvatarMode.custom;
  }

  Uri? _avatarUri(String path) {
    final value = widget.serverUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    final server = Uri.tryParse(value);
    return server?.resolve(path);
  }

  Future<void> _saveBuiltin() async {
    if (_saving || !isProfileBuiltinAvatar(_draftAvatar)) return;
    setState(() {
      _saving = true;
      _saveError = '';
    });
    try {
      final user = await widget.onSaveBuiltin(_draftAvatar);
      if (mounted) Navigator.pop(context, user);
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = '保存失败：${userFacingError(error)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCustom(Uint8List bytes) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = '';
    });
    try {
      final user = await widget.onSaveCustom(bytes);
      if (mounted) Navigator.pop(context, user);
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = '上传失败：${userFacingError(error)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = math.max(320.0, MediaQuery.sizeOf(context).height - 24);
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: height),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择头像',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('profile-avatar-close'),
                        tooltip: '关闭头像选择',
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_AvatarMode>(
                    segments: const [
                      ButtonSegment(
                        value: _AvatarMode.builtin,
                        icon: Icon(Icons.face_outlined),
                        label: Text('系统头像'),
                      ),
                      ButtonSegment(
                        value: _AvatarMode.custom,
                        icon: Icon(Icons.add_a_photo_outlined),
                        label: Text('自定义头像'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _saving
                        ? null
                        : (value) => setState(() {
                              _mode = value.single;
                              _saveError = '';
                            }),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _mode == _AvatarMode.builtin
                        ? _buildBuiltinPicker()
                        : SingleChildScrollView(
                            key: const ValueKey('profile-custom-avatar-scroll'),
                            child: _CustomAvatarPicker(
                              imagePicker: widget.imagePicker,
                              saving: _saving,
                              onSourceChanged: () =>
                                  setState(() => _saveError = ''),
                              onSave: _saveCustom,
                            ),
                          ),
                  ),
                  if (_saveError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _saveError,
                      key: const ValueKey('profile-avatar-save-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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

  Widget _buildBuiltinPicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 520 ? 8 : 4;
                return GridView.builder(
                  key: const ValueKey('profile-builtin-avatar-grid'),
                  itemCount: profileBuiltinAvatarCount,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final id = (index + 1).toString().padLeft(2, '0');
                    final path = profileBuiltinAvatarPath(index + 1);
                    final selected = _draftAvatar == path;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: '选择头像 $id',
                      child: Material(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          key: ValueKey('profile-builtin-avatar-$id'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: _saving
                              ? null
                              : () => setState(() {
                                    _draftAvatar = path;
                                    _saveError = '';
                                  }),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CachedAvatar(
                                repository: widget.repository,
                                cacheScope: widget.cacheScope,
                                avatarUri: _avatarUri(path),
                                name: id,
                                radius: 22,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              if (selected)
                                Positioned(
                                  right: 4,
                                  bottom: 4,
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('profile-builtin-avatar-save'),
              onPressed: _saving || !isProfileBuiltinAvatar(_draftAvatar)
                  ? null
                  : _saveBuiltin,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      );
}

class _CustomAvatarPicker extends StatefulWidget {
  const _CustomAvatarPicker({
    required this.imagePicker,
    required this.saving,
    required this.onSourceChanged,
    required this.onSave,
  });

  final ProfileAvatarImagePicker imagePicker;
  final bool saving;
  final VoidCallback onSourceChanged;
  final Future<void> Function(Uint8List bytes) onSave;

  @override
  State<_CustomAvatarPicker> createState() => _CustomAvatarPickerState();
}

class _CustomAvatarPickerState extends State<_CustomAvatarPicker> {
  static const _maxSourceBytes = 5 * 1024 * 1024;
  ProfileAvatarImage? _source;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  double _zoom = 1;
  double _focusX = 0.5;
  double _focusY = 0.5;
  String _error = '';

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
              key: const ValueKey('profile-custom-avatar-pick'),
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
                    key: const ValueKey('profile-custom-avatar-crop'),
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
                  key: const ValueKey('profile-custom-avatar-zoom'),
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
                key: const ValueKey('profile-custom-avatar-repick'),
                onPressed: widget.saving ? null : _pick,
                icon: const Icon(Icons.refresh),
                label: const Text('重新选择'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('profile-custom-avatar-save'),
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
            key: const ValueKey('profile-custom-avatar-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
