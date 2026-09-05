import 'package:flutter/material.dart';

import '../../data/storage_service.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({required this.service, super.key});

  final StorageService service;

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  late Future<StorageInfo> _infoFuture;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _infoFuture = widget.service.inspect();
  }

  Future<void> _reload() async {
    final future = widget.service.inspect();
    setState(() => _infoFuture = future);
    await future;
  }

  Future<void> _confirmClear(StoragePart part, String label) async {
    if (_clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清理$label？'),
        content: const Text('本操作只会删除本机离线副本，不影响服务器上的消息和文件。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清理')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.service.clear(part);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label已清理')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label清理失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('存储空间'),
          actions: [
            if (_clearing)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                  tooltip: '重新统计',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<StorageInfo>(
          future: _infoFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('统计失败，点击重试')),
              );
            }
            final info = snapshot.data;
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        children: [
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(children: [
                              _StorageStatTile(
                                  icon: Icons.photo_library_outlined,
                                  label: '媒体与文件',
                                  value: info?.formattedMedia ?? '统计中…'),
                              const Divider(height: 1, indent: 56),
                              _StorageStatTile(
                                  icon: Icons.forum_outlined,
                                  label: '离线消息',
                                  value: info?.formattedMessages ?? '统计中…'),
                              const Divider(height: 1, indent: 56),
                              _StorageStatTile(
                                  icon: Icons.storage_outlined,
                                  label: '总计',
                                  value: info?.formattedTotal ?? '统计中…'),
                            ]),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(children: [
                              _clearAction(
                                  icon: Icons.photo_library_outlined,
                                  label: '清理媒体与文件',
                                  part: StoragePart.media),
                              const Divider(height: 1, indent: 56),
                              _clearAction(
                                  icon: Icons.forum_outlined,
                                  label: '清理离线消息',
                                  part: StoragePart.messages),
                              const Divider(height: 1, indent: 56),
                              _clearAction(
                                  icon: Icons.delete_sweep_outlined,
                                  label: '清理全部',
                                  part: StoragePart.all),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '以上数据为本机全局统计，不区分账号。\n清理不会影响服务器数据。',
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
              ),
            );
          },
        ),
      );

  Widget _clearAction(
          {required IconData icon,
          required String label,
          required StoragePart part}) =>
      ListTile(
        enabled: !_clearing,
        leading: Icon(icon, color: Theme.of(context).colorScheme.error),
        title: Text(label,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _clearing
            ? null
            : () => _confirmClear(part, label.replaceFirst('清理', '')),
      );
}

class _StorageStatTile extends StatelessWidget {
  const _StorageStatTile(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
