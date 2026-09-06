import 'package:flutter/material.dart';
import '../../data/repository.dart';
import '../../domain/models.dart';
import '../shared/external_link_launcher.dart';
import '../shared/user_facing_error.dart';

Future<void> showHistoryAttachmentsDialog(
  BuildContext context, {
  required MagicChatRepository repository,
  required String conversationId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => HistoryAttachmentsDialog(
      repository: repository,
      conversationId: conversationId,
    ),
  );
}

class HistoryAttachmentsDialog extends StatefulWidget {
  const HistoryAttachmentsDialog({
    required this.repository,
    required this.conversationId,
    super.key,
  });

  final MagicChatRepository repository;
  final String conversationId;

  @override
  State<HistoryAttachmentsDialog> createState() =>
      _HistoryAttachmentsDialogState();
}

class _HistoryAttachmentsDialogState extends State<HistoryAttachmentsDialog> {
  final _attachments = <ConversationAttachment>[];
  String? _nextCursor;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    if (_loading || (next && _nextCursor == null)) return;
    final cursor = next ? _nextCursor : null;
    setState(() {
      _loading = true;
      if (!next) _error = null;
    });
    try {
      final page = await widget.repository.attachments(
        widget.conversationId,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        if (!next) _attachments.clear();
        final existing = _attachments.map((item) => item.messageId).toSet();
        _attachments.addAll(
            page.attachments.where((item) => existing.add(item.messageId)));
        final nextCursor = page.nextCursor?.trim();
        _nextCursor =
            nextCursor == null || nextCursor.isEmpty || nextCursor == cursor
                ? null
                : nextCursor;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ConversationAttachment attachment) async {
    try {
      final uri = await widget.repository.attachmentUrl(attachment.fileId);
      if (!mounted) return;
      if (uri == null) {
        _showError('无法打开附件');
        return;
      }
      final opened = await launchExternalWebLink(context, uri);
      if (opened == false) _showError('无法打开附件');
    } catch (error) {
      _showError('打开附件失败：${userFacingError(error)}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('历史附件'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: _buildContent(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );

  Widget _buildContent(BuildContext context) {
    if (_error != null && _attachments.isEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (_loading && _attachments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_attachments.isEmpty) {
      return const Center(child: Text('暂无历史附件'));
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _attachments.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final attachment = _attachments[index];
              return ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_formatSize(attachment.sizeBytes)} · ${_formatDate(attachment.createdAt)}',
                ),
                trailing: IconButton(
                  tooltip: '打开附件',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: _loading ? null : () => _open(attachment),
                ),
                onTap: _loading ? null : () => _open(attachment),
              );
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '加载下一页失败',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _loading ? null : () => _load(next: true),
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: const Text('加载更多'),
            ),
          ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }
}
