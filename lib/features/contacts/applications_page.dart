import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/avatar_processor.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';

/// Owned application management.  Keeping this flow outside `main.dart` makes
/// the contact directory and application lifecycle independently testable.
class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({required this.repository, this.serverUrl, super.key});

  final MagicChatRepository repository;
  final String? serverUrl;

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  Future<List<OwnedApp>>? _appsFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (!mounted) return;
    setState(() {
      _appsFuture = widget.repository.apps();
    });
  }

  Future<void> _create() async {
    final input = await _showAppForm();
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final credentials = await widget.repository.createApp(
        input.name,
        description: input.description,
        visibility: input.visibility,
        userIds: input.userIds,
      );
      if (!mounted) return;
      await _showCredentials(credentials);
      _load();
    } catch (error) {
      _showError('创建应用失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(OwnedApp app) async {
    final input = await _showAppForm(app: app);
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.updateApp(
        app.id,
        name: input.name,
        description: input.description,
        visibility: input.visibility,
        userIds: input.userIds,
      );
      _load();
    } catch (error) {
      _showError('保存应用失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCredentials(AppCredentials credentials) async {
    final server = widget.serverUrl?.replaceFirst(RegExp(r'/$'), '');
    final socket = server == null || server.isEmpty
        ? '/api/app/ws'
        : '${server.replaceFirst(RegExp(r'^http'), 'ws')}/api/app/ws';
    await showDialog<void>(
      context: context,
      builder: (context) => _CredentialsDialog(
        credentials: credentials,
        webSocketUrl: socket,
        onRegenerate: () async {
          return widget.repository.regenerateAppSecret(
            credentials.app.id,
          );
        },
      ),
    );
  }

  Future<void> _toggle(OwnedApp app) async {
    setState(() => _busy = true);
    try {
      await widget.repository.setAppEnabled(app.id, !app.enabled);
      _load();
    } catch (error) {
      _showError('更新应用状态失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadAvatar(OwnedApp app) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || !mounted) return;
    if (file.bytes == null) {
      _showError('当前平台无法读取头像内容');
      return;
    }
    late final Uint8List processed;
    try {
      processed = const AvatarProcessor().process(file.bytes!);
    } catch (error) {
      _showError('头像处理失败：$error');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.uploadAppAvatar(
        app.id,
        AttachmentUpload(
          path: '',
          name: 'app-avatar.webp',
          mimeType: 'image/webp',
          bytes: processed,
        ),
      );
      _load();
    } catch (error) {
      _showError('上传应用头像失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(OwnedApp app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除应用'),
        content: Text('确定删除“${app.name}”吗？删除后连接密钥立即失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.deleteApp(app.id);
      _load();
    } catch (error) {
      _showError('删除应用失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_AppFormInput?> _showAppForm({OwnedApp? app}) =>
      showDialog<_AppFormInput>(
        context: context,
        builder: (context) => _AppFormDialog(app: app),
      );

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的应用')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('创建应用'),
        ),
        body: FutureBuilder<List<OwnedApp>>(
          future: _appsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('加载失败，点击重试'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final apps = snapshot.data!;
            if (apps.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView(
                  children: const [
                    SizedBox(height: 220),
                    Center(child: Text('还没有应用')),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: apps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _AppCard(
                  app: apps[index],
                  serverUrl: widget.serverUrl,
                  busy: _busy,
                  onEdit: () => _edit(apps[index]),
                  onCredentials: () async {
                    setState(() => _busy = true);
                    try {
                      await _showCredentials(await widget.repository
                          .getAppCredentials(apps[index].id));
                    } catch (error) {
                      _showError('加载接入信息失败：$error');
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  onToggle: () => _toggle(apps[index]),
                  onAvatar: () => _uploadAvatar(apps[index]),
                  onDelete: () => _delete(apps[index]),
                ),
              ),
            );
          },
        ),
      );
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.serverUrl,
    required this.busy,
    required this.onEdit,
    required this.onCredentials,
    required this.onToggle,
    required this.onAvatar,
    required this.onDelete,
  });

  final OwnedApp app;
  final String? serverUrl;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onCredentials;
  final VoidCallback onToggle;
  final VoidCallback onAvatar;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            backgroundImage: _avatarProvider(app.avatar, serverUrl),
            child: Text(app.name.isEmpty ? '?' : app.name.substring(0, 1)),
          ),
          title: Row(
            children: [
              Flexible(child: Text(app.name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Chip(
                label: Text(app.enabled ? '已启用' : '已停用'),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: app.enabled
                    ? Colors.green.withValues(alpha: .12)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
          subtitle: Text(
            app.description.isEmpty
                ? '访问范围：${_visibilityLabel(app.visibility)}'
                : '${app.description}\n访问范围：${_visibilityLabel(app.visibility)}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: app.description.isNotEmpty,
          trailing: PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (value) {
              switch (value) {
                case 'credentials':
                  onCredentials();
                case 'edit':
                  onEdit();
                case 'toggle':
                  onToggle();
                case 'avatar':
                  onAvatar();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'credentials',
                child: Text('查看接入信息'),
              ),
              const PopupMenuItem(value: 'edit', child: Text('编辑资料')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(app.enabled ? '停用应用' : '启用应用'),
              ),
              const PopupMenuItem(value: 'avatar', child: Text('更换头像')),
              const PopupMenuItem(value: 'delete', child: Text('删除应用')),
            ],
          ),
        ),
      );

  String _visibilityLabel(String value) => switch (value) {
        'public' => '所有人',
        'restricted' => '部分用户',
        _ => '仅我自己',
      };

  ImageProvider<Object>? _avatarProvider(String value, String? serverUrl) {
    if (value.trim().isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed?.hasScheme == true) return NetworkImage(value);
    final server = Uri.tryParse(serverUrl ?? '');
    return server == null
        ? null
        : NetworkImage(server.resolve(value).toString());
  }
}

class _AppFormInput {
  const _AppFormInput({
    required this.name,
    required this.description,
    required this.visibility,
    required this.userIds,
  });

  final String name;
  final String description;
  final String visibility;
  final List<String> userIds;
}

class _AppFormDialog extends StatefulWidget {
  const _AppFormDialog({this.app});

  final OwnedApp? app;

  @override
  State<_AppFormDialog> createState() => _AppFormDialogState();
}

class _AppFormDialogState extends State<_AppFormDialog> {
  late final _name = TextEditingController(text: widget.app?.name ?? '');
  late final _description =
      TextEditingController(text: widget.app?.description ?? '');
  late final _users =
      TextEditingController(text: widget.app?.userIds.join(', ') ?? '');
  late String _visibility = widget.app?.visibility ?? 'creator';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _users.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final userIds = _users.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (name.isEmpty || (_visibility == 'restricted' && userIds.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写应用名称；限定用户模式至少需要一个用户 ID')));
      return;
    }
    Navigator.pop(
      context,
      _AppFormInput(
        name: name,
        description: _description.text.trim(),
        visibility: _visibility,
        userIds: userIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.app == null ? '创建应用' : '编辑应用资料'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '应用名称'),
                ),
                TextField(
                  controller: _description,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '应用描述'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _visibility,
                  decoration: const InputDecoration(labelText: '访问范围'),
                  items: const [
                    DropdownMenuItem(value: 'creator', child: Text('仅我自己')),
                    DropdownMenuItem(value: 'public', child: Text('所有人')),
                    DropdownMenuItem(value: 'restricted', child: Text('部分用户')),
                  ],
                  onChanged: (value) =>
                      setState(() => _visibility = value ?? 'creator'),
                ),
                if (_visibility == 'restricted')
                  TextField(
                    controller: _users,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '可访问用户 ID',
                      hintText: '多个 ID 用英文逗号分隔',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('保存')),
        ],
      );
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({
    required this.credentials,
    required this.webSocketUrl,
    required this.onRegenerate,
  });

  final AppCredentials credentials;
  final String webSocketUrl;
  final Future<AppCredentials> Function() onRegenerate;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late AppCredentials _credentials = widget.credentials;
  bool _resetting = false;

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置连接密钥'),
        content: const Text('重置后旧密钥立即失效，现有连接也会被断开。确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认重置')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resetting = true);
    try {
      _credentials = await widget.onRegenerate();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重置失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('应用接入信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CredentialField(label: '应用 ID', value: _credentials.app.id),
              _CredentialField(
                  label: 'WebSocket 地址', value: widget.webSocketUrl),
              _CredentialField(
                  label: '连接密钥', value: _credentials.connectionSecret),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _resetting ? null : _regenerate,
            child: const Text('重置连接密钥'),
          ),
          FilledButton(
              onPressed: _resetting ? null : () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      );
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: IconButton(
              tooltip: '复制$label',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$label已复制')));
                }
              },
            ),
          ),
          child: SelectableText(value),
        ),
      );
}
