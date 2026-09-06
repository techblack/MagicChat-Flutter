import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/message_cache_store.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/cached_avatar.dart';
import '../shared/user_facing_error.dart';
import 'contact_directory_model.dart';

typedef ContactConversationSource = ({
  Contact contact,
  ContactDirectoryCategory? category,
});
typedef ContactConversationCallback = void Function(
    String conversationId, ContactConversationSource? source);

class EntityDetailsPage extends StatefulWidget {
  const EntityDetailsPage({
    required this.repository,
    required this.contact,
    this.serverUrl,
    this.cacheScope,
    this.sourceCategory,
    this.onOpenConversation,
    super.key,
  });

  final MagicChatRepository repository;
  final Contact contact;
  final String? serverUrl;
  final MessageCacheScope? cacheScope;
  final ContactDirectoryCategory? sourceCategory;
  final ContactConversationCallback? onOpenConversation;

  @override
  State<EntityDetailsPage> createState() => _EntityDetailsPageState();
}

class _EntityDetailsPageState extends State<EntityDetailsPage> {
  late Future<_EntityDetailsData> _future = _load();
  bool _openingConversation = false;

  Future<_EntityDetailsData> _load() async {
    final currentUser = await widget.repository.currentUser();
    var contact = widget.contact;
    if (contact.type == 'user') {
      final resolved = await widget.repository.resolveUsers([contact.id]);
      if (resolved.isNotEmpty) contact = resolved.first;
    } else {
      final directory = await widget.repository
          .contactDirectory(keyword: contact.displayName);
      contact = directory.contacts
              .where((item) =>
                  item.id.toLowerCase() == contact.id.toLowerCase() &&
                  item.type == contact.type)
              .firstOrNull ??
          contact;
    }

    String? developerName;
    final creatorUserId = contact.creatorUserId;
    if (contact.type == 'app' && creatorUserId != null) {
      if (creatorUserId.toLowerCase() == currentUser.id.toLowerCase()) {
        developerName = currentUser.displayName;
      } else {
        final creators = await widget.repository.resolveUsers([creatorUserId]);
        if (creators.isNotEmpty) developerName = creators.first.displayName;
      }
    }
    return _EntityDetailsData(
        contact: contact,
        currentUserId: currentUser.id,
        developerName: developerName);
  }

  Future<void> _openConversation(Contact contact) async {
    if (_openingConversation) return;
    final data = await _future;
    if (!mounted ||
        (contact.type == 'user' &&
            contact.id.toLowerCase() == data.currentUserId.toLowerCase())) {
      return;
    }
    setState(() => _openingConversation = true);
    try {
      final conversation = contact.type == 'app'
          ? await widget.repository.createAppConversation(contact.id)
          : contact.type == 'group'
              ? contact.joined
                  ? await widget.repository.restoreConversation(contact.id)
                  : await widget.repository.joinGroupConversation(contact.id)
              : await widget.repository.createDirectConversation(contact.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onOpenConversation?.call(
          conversation.id, (contact: contact, category: widget.sourceCategory));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_actionError(contact, userFacingError(error)))));
      }
    } finally {
      if (mounted) setState(() => _openingConversation = false);
    }
  }

  String _actionError(Contact contact, String detail) => contact.type == 'group'
      ? '无法加入群聊：$detail'
      : contact.type == 'app'
          ? '无法发起应用会话：$detail'
          : '无法发起私聊：$detail';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_pageTitle(widget.contact.type))),
        body: FutureBuilder<_EntityDetailsData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _future = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('资料加载失败，点击重试'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content(snapshot.data!);
          },
        ),
      );

  Widget _content(_EntityDetailsData data) {
    final contact = data.contact;
    final avatarUri = _entityAvatarUri(widget.serverUrl, contact.avatar);
    final ownProfile = contact.type == 'user' &&
        contact.id.toLowerCase() == data.currentUserId.toLowerCase();
    final fields = _profileFields(contact, data.developerName);
    final actionLabel =
        contact.type == 'group' && !contact.joined ? '加入群聊' : '发消息';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(children: [
              Semantics(
                button: avatarUri != null,
                label: avatarUri == null ? null : '查看${contact.displayName}的头像',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: avatarUri == null
                      ? null
                      : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _AvatarPreviewPage(
                                repository: widget.repository,
                                uri: avatarUri,
                                name: contact.displayName,
                              ),
                            ),
                          ),
                  child: CachedAvatar(
                    repository: widget.repository,
                    cacheScope: widget.cacheScope,
                    avatarUri: avatarUri,
                    name: contact.displayName,
                    radius: 48,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(contact.displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(_profileKind(contact),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (contact.type == 'app' &&
                  contact.description.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(contact.description.trim(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              Card(
                child: Column(
                  children: [
                    for (var index = 0; index < fields.length; index++) ...[
                      if (index > 0) const Divider(height: 1, indent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Row(children: [
                          Expanded(flex: 2, child: Text(fields[index].label)),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: Text(fields[index].value,
                                textAlign: TextAlign.end,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
              if (!ownProfile) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openingConversation
                        ? null
                        : () => _openConversation(contact),
                    icon: _openingConversation
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(contact.type == 'group' && !contact.joined
                            ? Icons.group_add_outlined
                            : Icons.chat_bubble_outline),
                    label: Text(actionLabel),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _AvatarPreviewPage extends StatefulWidget {
  const _AvatarPreviewPage(
      {required this.repository, required this.uri, required this.name});

  final MagicChatRepository repository;
  final Uri uri;
  final String name;

  @override
  State<_AvatarPreviewPage> createState() => _AvatarPreviewPageState();
}

class _AvatarPreviewPageState extends State<_AvatarPreviewPage> {
  late final Future<Uint8List?> _bytes =
      widget.repository.downloadResource(widget.uri);
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _bytes;
      if (bytes == null || bytes.isEmpty) throw StateError('头像内容为空');
      final extension = _imageExtension(widget.uri.path);
      final path = await FilePicker.saveFile(
          dialogTitle: '保存头像',
          fileName: 'MagicChat-avatar.$extension',
          bytes: bytes);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('头像保存失败：${userFacingError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${widget.name}的头像'),
          actions: [
            IconButton(
              tooltip: '保存头像',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined),
            ),
          ],
        ),
        body: Center(
          child: FutureBuilder<Uint8List?>(
            future: _bytes,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes != null && bytes.isNotEmpty) {
                return InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.memory(bytes, fit: BoxFit.contain));
              }
              if (snapshot.hasError) {
                return const Text('头像加载失败',
                    style: TextStyle(color: Colors.white));
              }
              return const CircularProgressIndicator();
            },
          ),
        ),
      );
}

class _EntityDetailsData {
  const _EntityDetailsData(
      {required this.contact, required this.currentUserId, this.developerName});

  final Contact contact;
  final String currentUserId;
  final String? developerName;
}

typedef _ProfileField = ({String label, String value});

List<_ProfileField> _profileFields(Contact contact, String? developerName) {
  if (contact.type == 'user') {
    return [
      (label: '姓名', value: _fieldValue(contact.name, contact.id)),
      (label: '昵称', value: _fieldValue(contact.nickname, contact.id)),
      (label: '邮箱', value: _fieldValue(contact.email, contact.id)),
      (label: '手机', value: _fieldValue(contact.phone, contact.id)),
    ];
  }
  if (contact.type == 'app') {
    return [
      (label: '类型', value: '应用'),
      if (developerName?.trim().isNotEmpty == true)
        (label: '开发者', value: developerName!.trim()),
      (label: '状态', value: contact.online ? '在线' : '离线'),
    ];
  }
  return [
    (label: '类型', value: '群聊'),
    (label: '成员', value: '${contact.memberCount} 人群聊'),
    (label: '状态', value: contact.joined ? '已加入' : '未加入'),
  ];
}

String _fieldValue(String value, String id) {
  final text = value.trim();
  return text.isEmpty ||
          text.toLowerCase() == id.trim().toLowerCase() ||
          text == '成员' ||
          text == '用户'
      ? '未设置'
      : text;
}

String _profileKind(Contact contact) => switch (contact.type) {
      'app' => '应用资料',
      'group' => '群聊资料',
      _ => '用户资料',
    };

String _pageTitle(String type) => switch (type) {
      'app' => '应用详情',
      'group' => '群组详情',
      _ => '联系人详情',
    };

Uri? _entityAvatarUri(String? serverUrl, String value) {
  if (value.trim().isEmpty) return null;
  final parsed = Uri.tryParse(value);
  if (parsed == null) return null;
  if (parsed.hasScheme) return parsed;
  final server = Uri.tryParse(serverUrl ?? '');
  return server?.resolve(value);
}

String _imageExtension(String path) {
  final extension = path.split('.').last.toLowerCase();
  return const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)
      ? extension
      : 'jpg';
}
