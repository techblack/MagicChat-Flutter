import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/cached_avatar.dart';
import '../shared/custom_avatar_picker.dart';
import '../shared/user_facing_error.dart';

const profileBuiltinAvatarCount = 64;

String profileBuiltinAvatarPath(int index) =>
    '/assets/avatars/builtin/${index.toString().padLeft(2, '0')}.webp';

bool isProfileBuiltinAvatar(String value) =>
    RegExp(r'^/assets/avatars/builtin/(0[1-9]|[1-5][0-9]|6[0-4])\.webp$')
        .hasMatch(value);

class ProfileAvatarImage extends AvatarPickerImage {
  const ProfileAvatarImage({required super.name, required super.bytes});
}

typedef ProfileAvatarImagePicker = Future<ProfileAvatarImage?> Function();

Future<ProfileAvatarImage?> pickProfileAvatarImage() async {
  final image = await pickAvatarImage();
  if (image == null) return null;
  return ProfileAvatarImage(name: image.name, bytes: image.bytes);
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
                            child: CustomAvatarPicker(
                              keyPrefix: 'profile-custom-avatar',
                              imagePicker: () => widget.imagePicker(),
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
