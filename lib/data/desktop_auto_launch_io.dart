import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'desktop_auto_launch_types.dart';

typedef DesktopProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class DesktopAutoLaunchService implements DesktopAutoLaunchController {
  DesktopAutoLaunchService({
    TargetPlatform? platform,
    String? executablePath,
    String? homeDirectory,
    Map<String, String>? environment,
    DesktopProcessRunner? processRunner,
  })  : _platform = platform ?? defaultTargetPlatform,
        _executablePath = executablePath ?? Platform.resolvedExecutable,
        _homeDirectory = homeDirectory,
        _environment = environment ?? Platform.environment,
        _processRunner = processRunner ?? _runProcess;

  static const _applicationId = 'cloud.baizhi.chat';
  static const _windowsRunKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _windowsValueName = 'MagicChat';

  final TargetPlatform _platform;
  final String _executablePath;
  final String? _homeDirectory;
  final Map<String, String> _environment;
  final DesktopProcessRunner _processRunner;

  @override
  bool get isSupported =>
      _platform == TargetPlatform.windows ||
      _platform == TargetPlatform.macOS ||
      _platform == TargetPlatform.linux;

  @override
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    if (_platform == TargetPlatform.windows) {
      final result = await _processRunner('reg.exe', [
        'query',
        _windowsRunKey,
        '/v',
        _windowsValueName,
      ]);
      if (result.exitCode != 0) return false;
      return '${result.stdout}'.contains(
        windowsAutoLaunchCommand(_executablePath),
      );
    }
    final file = File(await registrationPath());
    if (!await file.exists()) return false;
    try {
      final content = await file.readAsString();
      return _platform == TargetPlatform.macOS
          ? content.contains(
                '<string>${_xmlEscape(_executablePath)}</string>',
              ) &&
              content.contains('<string>--hidden</string>')
          : content.contains(
              'Exec="${escapeDesktopEntryArgument(_executablePath)}" --hidden',
            );
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) {
      throw const DesktopAutoLaunchException('当前平台不支持开机自动启动');
    }
    if (_platform == TargetPlatform.windows) {
      final result = enabled
          ? await _processRunner('reg.exe', [
              'add',
              _windowsRunKey,
              '/v',
              _windowsValueName,
              '/t',
              'REG_SZ',
              '/d',
              windowsAutoLaunchCommand(_executablePath),
              '/f',
            ])
          : await _processRunner('reg.exe', [
              'delete',
              _windowsRunKey,
              '/v',
              _windowsValueName,
              '/f',
            ]);
      if (result.exitCode != 0 && (enabled || result.exitCode != 1)) {
        throw DesktopAutoLaunchException(
          '系统启动项设置失败：${'${result.stderr}'.trim()}',
        );
      }
      return;
    }

    final path = await registrationPath();
    final file = File(path);
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final content = _platform == TargetPlatform.macOS
        ? macOSLaunchAgent(_executablePath)
        : linuxAutoStartEntry(_executablePath);
    final temporary = File(
      '$path.${pid}_${DateTime.now().microsecondsSinceEpoch.toString()}.tmp',
    );
    try {
      await temporary.writeAsString(content, flush: true);
      if (_platform == TargetPlatform.linux) {
        await Process.run('chmod', ['600', temporary.path]);
      }
      await temporary.rename(path);
    } on FileSystemException catch (error) {
      if (await temporary.exists()) await temporary.delete();
      throw DesktopAutoLaunchException('系统启动项设置失败：${error.message}');
    }
  }

  @visibleForTesting
  Future<String> registrationPath() async {
    final home = _homeDirectory ?? _environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      throw const DesktopAutoLaunchException('无法确定当前用户目录');
    }
    if (_platform == TargetPlatform.macOS) {
      return p.join(
        home,
        'Library',
        'LaunchAgents',
        '$_applicationId.autostart.plist',
      );
    }
    final config = _environment['XDG_CONFIG_HOME']?.trim();
    final root =
        config == null || config.isEmpty ? p.join(home, '.config') : config;
    return p.join(root, 'autostart', '$_applicationId.desktop');
  }
}

String windowsAutoLaunchCommand(String executable) => '"$executable" --hidden';

String escapeDesktopEntryArgument(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('%', '%%');

String linuxAutoStartEntry(String executable) => '''[Desktop Entry]
Type=Application
Name=MagicChat
Exec="${escapeDesktopEntryArgument(executable)}" --hidden
Terminal=false
X-GNOME-Autostart-enabled=true
''';

String macOSLaunchAgent(String executable) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>cloud.baizhi.chat.autostart</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(executable)}</string>
    <string>--hidden</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
''';

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Process.run(executable, arguments);
