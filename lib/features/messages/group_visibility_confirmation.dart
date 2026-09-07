import 'package:flutter/material.dart';

import '../shared/user_facing_error.dart';

String groupVisibilityConfirmationTitle(bool makePublic) =>
    makePublic ? '设为公开群聊？' : '设为私有群聊？';

String groupVisibilityImpactDescription(bool makePublic) => makePublic
    ? '设为公开群聊后，所有用户都可以在通讯录中发现并加入该群聊。'
    : '设为私有群聊后，未加入的用户将不能再从通讯录加入该群聊。';

Future<bool> showGroupVisibilityConfirmationDialog(
  BuildContext context, {
  required bool makePublic,
  required Future<void> Function() onConfirm,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _GroupVisibilityConfirmationDialog(
          makePublic: makePublic,
          onConfirm: onConfirm,
        ),
      ) ??
      false;
}

class _GroupVisibilityConfirmationDialog extends StatefulWidget {
  const _GroupVisibilityConfirmationDialog({
    required this.makePublic,
    required this.onConfirm,
  });

  final bool makePublic;
  final Future<void> Function() onConfirm;

  @override
  State<_GroupVisibilityConfirmationDialog> createState() =>
      _GroupVisibilityConfirmationDialogState();
}

class _GroupVisibilityConfirmationDialogState
    extends State<_GroupVisibilityConfirmationDialog> {
  bool _submitting = false;
  String _error = '';

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '更新失败：${userFacingError(error)}');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_submitting,
        child: AlertDialog(
          key: const ValueKey('group-visibility-confirmation-dialog'),
          title: Text(groupVisibilityConfirmationTitle(widget.makePublic)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(groupVisibilityImpactDescription(widget.makePublic)),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _error,
                  key: const ValueKey('group-visibility-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('group-visibility-cancel'),
              onPressed:
                  _submitting ? null : () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('group-visibility-confirm'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认'),
            ),
          ],
        ),
      );
}
