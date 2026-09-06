import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/desktop_screenshot.dart';

class DesktopScreenshotShortcutDialog extends StatefulWidget {
  const DesktopScreenshotShortcutDialog({
    required this.initial,
    required this.platform,
    super.key,
  });

  final DesktopScreenshotShortcut initial;
  final TargetPlatform platform;

  @override
  State<DesktopScreenshotShortcutDialog> createState() =>
      _DesktopScreenshotShortcutDialogState();
}

class _DesktopScreenshotShortcutDialogState
    extends State<DesktopScreenshotShortcutDialog> {
  final _focusNode = FocusNode();
  late DesktopScreenshotShortcut _shortcut;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shortcut = widget.initial;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _record(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _modifierKeys.contains(event.physicalKey)) {
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifiers = <DesktopShortcutModifier>{
      if (keyboard.isControlPressed) DesktopShortcutModifier.control,
      if (keyboard.isMetaPressed) DesktopShortcutModifier.meta,
      if (keyboard.isAltPressed) DesktopShortcutModifier.alt,
      if (keyboard.isShiftPressed) DesktopShortcutModifier.shift,
    };
    final next = DesktopScreenshotShortcut(
      keyCode: event.physicalKey.usbHidUsage,
      modifiers: modifiers,
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
        title: const Text('修改截图快捷键'),
        content: SizedBox(
          width: 380,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _record,
            child: Container(
              key: const ValueKey('desktop-screenshot-shortcut-recorder'),
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
                  key: const ValueKey('desktop-screenshot-shortcut-label'),
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
              _shortcut = DesktopScreenshotShortcut.defaultFor(widget.platform);
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

final _modifierKeys = {
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
};
