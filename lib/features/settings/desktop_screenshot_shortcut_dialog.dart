import 'package:flutter/material.dart';

import '../../data/desktop_screenshot.dart';
import 'desktop_shortcut_dialog.dart';

class DesktopScreenshotShortcutDialog extends StatelessWidget {
  const DesktopScreenshotShortcutDialog({
    required this.initial,
    required this.platform,
    super.key,
  });

  final DesktopScreenshotShortcut initial;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) =>
      DesktopShortcutDialog<DesktopScreenshotShortcut>(
        title: '修改截图快捷键',
        initial: initial,
        defaultShortcut: DesktopScreenshotShortcut.defaultFor(platform),
        platform: platform,
        recorderKey: const ValueKey('desktop-screenshot-shortcut-recorder'),
        labelKey: const ValueKey('desktop-screenshot-shortcut-label'),
        createShortcut: ({
          required keyCode,
          required modifiers,
          required enabled,
        }) =>
            DesktopScreenshotShortcut(
          keyCode: keyCode,
          modifiers: modifiers,
          enabled: enabled,
        ),
      );
}
