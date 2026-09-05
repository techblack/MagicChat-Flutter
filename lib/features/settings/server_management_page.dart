import 'package:flutter/material.dart';

import '../../data/auth_service.dart';
import '../../data/server_store.dart';

class ServerManagementPage extends StatefulWidget {
  const ServerManagementPage({
    required this.store,
    this.activeServerUrl,
    this.onSelect,
    super.key,
  });

  final ServerStore store;
  final String? activeServerUrl;
  final Future<void> Function(StoredServer server)? onSelect;

  @override
  State<ServerManagementPage> createState() => _ServerManagementPageState();
}

class _ServerManagementPageState extends State<ServerManagementPage> {
  late Future<ServerState> _stateFuture = widget.store.read();
  bool _busy = false;

  void _reload() => setState(() {
        _stateFuture = widget.store.read();
      });

  bool _isActive(StoredServer server) {
    final active = widget.activeServerUrl;
    return active != null && active == server.url;
  }

  Future<void> _select(StoredServer server) async {
    if (_busy) return;
    final callback = widget.onSelect;
    if (callback == null) {
      await widget.store.select(server.id);
      if (mounted) Navigator.pop(context, server.url);
      return;
    }
    if (_isActive(server)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换服务器？'),
        content: Text('将切换到“${server.name}”并返回登录页，当前账号仍会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('切换')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.store.select(server.id);
      await callback(server);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('切换失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(StoredServer? server) async {
    if (_busy || server?.builtIn == true) return;
    final input = await showDialog<({String name, String url})>(
      context: context,
      builder: (context) => _ServerEditorDialog(server: server),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = server == null
          ? await widget.store.add(input.name, input.url)
          : await widget.store.update(server.id, input.name, input.url);
      if (!mounted) return;
      if (result.status == SaveServerStatus.duplicate) {
        _showMessage('该服务器地址已经存在');
        return;
      }
      if (result.status == SaveServerStatus.invalid) {
        _showMessage('请填写服务器名称和有效的 HTTP(S) 地址');
        return;
      }
      if (result.status == SaveServerStatus.notFound) {
        _showMessage('该服务器已不存在');
        return;
      }
      _reload();
      final updated = result.server;
      if (server != null &&
          updated != null &&
          _isActive(server) &&
          server.url != updated.url &&
          widget.onSelect != null) {
        await widget.store.select(updated.id);
        await widget.onSelect!(updated);
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) _showMessage('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(StoredServer server) async {
    if (_busy || server.builtIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器？'),
        content: Text('确定删除“${server.name}”吗？已保存账号不会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.store.remove(server.id);
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('服务器管理'),
          actions: [
            IconButton(
                tooltip: '添加服务器',
                onPressed: _busy ? null : () => _edit(null),
                icon: const Icon(Icons.add)),
          ],
        ),
        body: FutureBuilder<ServerState>(
          future: _stateFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('服务器列表加载失败，点击重试')),
              );
            }
            final state = snapshot.data;
            if (state == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('选择服务器',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var index = 0;
                                  index < state.servers.length;
                                  index++) ...[
                                if (index > 0)
                                  const Divider(height: 1, indent: 56),
                                _serverTile(state, state.servers[index]),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _edit(null),
                          icon: const Icon(Icons.add),
                          label: const Text('添加服务器'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '服务器配置只保存在本机；删除服务器不会删除该服务器上的账号。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _serverTile(ServerState state, StoredServer server) {
    final active = _isActive(server);
    final selected = server.id == state.selectedServerId;
    final recent = server.id == state.recentServerId;
    return ListTile(
      enabled: !_busy,
      leading: Icon(active || selected
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked),
      title: Row(children: [
        Expanded(
            child: Text(server.name,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (active)
          const Padding(
              padding: EdgeInsets.only(left: 8),
              child:
                  Chip(label: Text('当前'), visualDensity: VisualDensity.compact))
        else if (recent)
          const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Chip(
                  label: Text('最近使用'), visualDensity: VisualDensity.compact)),
      ]),
      subtitle: Text(server.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: server.builtIn
          ? const Icon(Icons.verified_outlined, semanticLabel: '内置服务器')
          : PopupMenuButton<String>(
              tooltip: '服务器操作',
              onSelected: (action) {
                if (action == 'edit') {
                  _edit(server);
                } else if (action == 'delete') {
                  _remove(server);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('修改')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
      onTap: _busy ? null : () => _select(server),
    );
  }
}

class _ServerEditorDialog extends StatefulWidget {
  const _ServerEditorDialog({this.server});

  final StoredServer? server;

  @override
  State<_ServerEditorDialog> createState() => _ServerEditorDialogState();
}

class _ServerEditorDialogState extends State<_ServerEditorDialog> {
  late final _name = TextEditingController(text: widget.server?.name ?? '');
  late final _url = TextEditingController(text: widget.server?.url ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入服务器名称');
      return;
    }
    String url;
    try {
      url = normalizeServerUrl(_url.text);
    } catch (_) {
      setState(() => _error = '请输入有效的 HTTP(S) 服务器地址');
      return;
    }
    Navigator.pop(context, (name: name, url: url));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.server == null ? '添加服务器' : '修改服务器'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('server-name-field'),
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration:
                    const InputDecoration(labelText: '名称', hintText: '服务器名称'),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('server-url-field'),
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                    labelText: '地址', hintText: 'https://example.com'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('保存')),
        ],
      );
}
