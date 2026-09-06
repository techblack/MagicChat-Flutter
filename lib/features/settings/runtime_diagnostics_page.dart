import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/chat_preferences.dart';
import '../../data/local_notification_service.dart';
import '../../data/realtime.dart';
import '../../data/runtime_diagnostics.dart';
import '../../data/storage_service.dart';

class RuntimeDiagnosticsPage extends StatefulWidget {
  const RuntimeDiagnosticsPage({required this.source, super.key});

  final RuntimeDiagnosticsSource source;

  @override
  State<RuntimeDiagnosticsPage> createState() => _RuntimeDiagnosticsPageState();
}

class _RuntimeDiagnosticsPageState extends State<RuntimeDiagnosticsPage> {
  RuntimeDiagnosticsView? _view;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final view = await widget.source.refresh();
      if (mounted) setState(() => _view = view);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyReport() async {
    final view = _view;
    if (view == null) return;
    await Clipboard.setData(
      ClipboardData(text: widget.source.buildReport(view)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('脱敏诊断报告已复制')));
    }
  }

  Future<void> _clearRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理诊断记录？'),
        content: const Text('将删除本机保存的运行诊断记录，不会清理消息和媒体缓存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final stats = await widget.source.clearRecords();
      if (!mounted) return;
      setState(() {
        final current = _view;
        if (current != null) _view = current.withRecordStats(stats);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('诊断记录已清理')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('诊断记录清理失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('连接与运行诊断'),
          actions: [
            IconButton(
              tooltip: '复制脱敏报告',
              onPressed: _view == null ? null : _copyReport,
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: '刷新诊断',
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _body(),
      );

  Widget _body() {
    final view = _view;
    if (_loading && view == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && view == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('诊断加载失败'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (view == null) return const SizedBox.shrink();
    final snapshot = view.snapshot;
    return SelectionArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            if (_failed)
              const Card(
                color: Colors.orangeAccent,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('本次刷新失败，正在展示上一次诊断结果。'),
                ),
              ),
            _section(
              context,
              icon: Icons.computer_outlined,
              title: '客户端环境',
              children: [
                _row('平台', snapshot.platform),
                _row('版本', '${snapshot.version} · ${snapshot.buildMode}'),
                _row(
                  '服务器',
                  snapshot.server,
                  key: const ValueKey('diagnostics-server'),
                ),
                _row('采集时间', _formatTime(snapshot.capturedAt)),
              ],
            ),
            _section(
              context,
              icon: snapshot.http.reachedServer
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              title: 'HTTP 连接',
              children: [
                _row('可达性', _httpLabel(snapshot.http)),
                _row('往返延迟', '${snapshot.http.latencyMs} ms'),
                if (snapshot.http.statusCode != null)
                  _row('响应状态', 'HTTP ${snapshot.http.statusCode}'),
              ],
            ),
            _section(
              context,
              icon: Icons.sync_outlined,
              title: '实时连接',
              children: [
                _row('连接状态', _realtimeLabel(snapshot.realtimeStatus)),
                _row('协议就绪', snapshot.realtimeReady ? '是' : '否'),
                _row('重连状态', _reconnectLabel(snapshot)),
                _row('本机游标', '${snapshot.realtimeCursor}'),
              ],
            ),
            _section(
              context,
              icon: Icons.storage_outlined,
              title: '缓存与存储',
              children: [
                _row('状态', snapshot.cacheAvailable ? '可用' : '暂不可用'),
                _row('离线消息', formatStorageSize(snapshot.messageCacheBytes)),
                _row('媒体与文件', formatStorageSize(snapshot.mediaCacheBytes)),
                _row(
                  '数据库/WAL',
                  _journalModes(snapshot.cacheJournalModes),
                  key: const ValueKey('diagnostics-journal-modes'),
                ),
                _row(
                  '已载入数据',
                  '${snapshot.cachedConversationCount} 个会话 · ${snapshot.loadedMessageCount} 条消息',
                ),
              ],
            ),
            _section(
              context,
              icon: Icons.notifications_outlined,
              title: '通知与权限',
              children: [
                _row('应用通知', snapshot.notificationsEnabled ? '已开启' : '已关闭'),
                _row(
                  '系统权限',
                  _notificationPermissionLabel(snapshot.notificationPermission),
                ),
                _row('提示音', snapshot.messageSoundEnabled ? '已开启' : '已关闭'),
                _row('隐私级别', _privacyLabel(snapshot.notificationPrivacy)),
              ],
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    const Icon(Icons.history_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '本地诊断记录',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${view.recordStats.count} 条 · ${formatStorageSize(view.recordStats.bytes)}',
                            key: const ValueKey('diagnostics-record-stats'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          view.recordStats.count == 0 ? null : _clearRecords,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清理记录'),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                '诊断只保存在本机；报告不包含令牌、Cookie、邮箱、消息正文或完整错误文本。客户端未观察到事件，不代表服务端未发送。',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              ListTile(
                leading: Icon(icon),
                title:
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              ...children,
            ],
          ),
        ),
      );

  Widget _row(String label, String value, {Key? key}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(child: SelectableText(value, key: key)),
          ],
        ),
      );

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _httpLabel(HttpProbeResult probe) => switch (probe.state) {
        HttpProbeState.reachable => '可达且认证有效',
        HttpProbeState.unauthorized => '可达，登录状态失效',
        HttpProbeState.serverError => '可达，服务端返回错误',
        HttpProbeState.invalidResponse => '可达，响应格式异常',
        HttpProbeState.unreachable => '不可达',
      };

  String _realtimeLabel(RealtimeStatus? status) => switch (status) {
        RealtimeStatus.connected => '已连接',
        RealtimeStatus.connecting => '连接中',
        RealtimeStatus.reconnecting => '重连中',
        RealtimeStatus.disconnected => '已断开',
        null => '不可用',
      };

  String _reconnectLabel(RuntimeDiagnosticsSnapshot snapshot) {
    if (snapshot.realtimeStatus != RealtimeStatus.reconnecting) return '无需重连';
    final delay = snapshot.reconnectDelayMs;
    return '第 ${snapshot.reconnectAttempt} 次'
        '${delay == null ? '' : ' · 计划延迟 $delay ms'}';
  }

  String _journalModes(Map<String, String> values) {
    if (values.isEmpty) return '尚未初始化';
    const labels = {'direct': '私聊', 'group': '群聊', 'app': '应用', 'topic': '话题'};
    return values.entries
        .map((entry) => '${labels[entry.key] ?? entry.key}: ${entry.value}')
        .join(' · ');
  }

  String _notificationPermissionLabel(NotificationPermissionStatus value) =>
      switch (value) {
        NotificationPermissionStatus.granted => '已授权',
        NotificationPermissionStatus.denied => '已拒绝',
        NotificationPermissionStatus.notDetermined => '尚未询问',
        NotificationPermissionStatus.unsupported => '当前平台无法读取',
        NotificationPermissionStatus.unknown => '状态未知',
      };

  String _privacyLabel(MessageNotificationPrivacy value) => switch (value) {
        MessageNotificationPrivacy.hidden => '隐藏内容',
        MessageNotificationPrivacy.metadata => '仅显示来源',
        MessageNotificationPrivacy.preview => '显示预览',
      };
}
