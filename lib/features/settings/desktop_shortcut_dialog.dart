import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/desktop_shortcut.dart';

typedef DesktopShortcutFactory<T extends DesktopGlobalShortcut> = T Function({
  required int keyCode,
  required Set<DesktopShortcutModifier> modifiers,
  required bool enabled,
});

class DesktopShortcutDialog<T extends DesktopGlobalShortcut>
    extends StatefulWidget {
  const DesktopShortcutDialog({
    required this.title,
    required this.initial,
    required this.defaultShortcut,
    required this.platform,
    required this.createShortcut,
    required this.recorderKey,
    required this.labelKey,
    super.key,
  });

  final String title;
  final T initial;
  final T defaultShortcut;
  final TargetPlatform platform;
  final DesktopShortcutFactory<T> createShortcut;
  final Key recorderKey;
  final Key labelKey;

  @override
  State<DesktopShortcutDialog<T>> createState() =>
      _DesktopShortcutDialogState<T>();
}

class _DesktopShortcutDialogState<T extends DesktopGlobalShortcut>
    extends State<DesktopShortcutDialog<T>> {
  final _focusNode = FocusNode();
  late T _shortcut = widget.initial;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _record(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        desktopShortcutModifierKeys.contains(event.physicalKey)) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final next = widget.createShortcut(
      keyCode: event.physicalKey.usbHidUsage,
      modifiers: {
        if (keyboard.isControlPressed) DesktopShortcutModifier.control,
        if (keyboard.isMetaPressed) DesktopShortcutModifier.meta,
        if (keyboard.isAltPressed) DesktopShortcutModifier.alt,
        if (keyboard.isShiftPressed) DesktopShortcutModifier.shift,
      },
      enabled: true,
    );
    setState(() {
      _shortcut = next;
      _error = next.isValid ? null : '快捷键需要包含 Ctrl、Command/Win 或 Alt';
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 380,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _record,
            child: Container(
              key: widget.recorderKey,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('请按下新的组合键'),
                const SizedBox(height: 12),
                Text(
                  _shortcut.label(widget.platform),
                  key: widget.labelKey,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _shortcut = widget.defaultShortcut;
              _error = null;
              _focusNode.requestFocus();
            }),
            child: const Text('恢复默认'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: _shortcut.isValid
                ? () => Navigator.pop(context, _shortcut)
                : null,
            child: const Text('保存'),
          ),
        ],
      );
}
