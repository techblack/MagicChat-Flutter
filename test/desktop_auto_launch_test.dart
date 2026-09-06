import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/desktop_auto_launch.dart';
import 'package:magicchat_client/data/desktop_auto_launch_io.dart'
    as desktop_io;

void main() {
  group('桌面开机自动启动', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('magicchat-autostart-');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('Linux 写入真实 XDG 启动项并带 hidden 参数', () async {
      final service = desktop_io.DesktopAutoLaunchService(
        platform: TargetPlatform.linux,
        executablePath: '/opt/Magic Chat/magicchat',
        homeDirectory: directory.path,
        environment: {'XDG_CONFIG_HOME': directory.path},
      );

      expect(await service.isEnabled(), isFalse);
      await service.setEnabled(true);

      final file = File(await service.registrationPath());
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), contains('Type=Application'));
      expect(
        await file.readAsString(),
        contains('Exec="/opt/Magic Chat/magicchat" --hidden'),
      );
      expect(await service.isEnabled(), isTrue);

      await service.setEnabled(false);
      expect(await file.exists(), isFalse);
      expect(await service.isEnabled(), isFalse);
    });

    test('macOS LaunchAgent 使用 ProgramArguments 传入 hidden', () async {
      final service = desktop_io.DesktopAutoLaunchService(
        platform: TargetPlatform.macOS,
        executablePath: '/Applications/Magic&Chat.app/Contents/MacOS/MagicChat',
        homeDirectory: directory.path,
        environment: const {},
      );

      await service.setEnabled(true);
      final content =
          await File(await service.registrationPath()).readAsString();

      expect(content, contains('cloud.baizhi.chat.autostart'));
      expect(content, contains('Magic&amp;Chat.app'));
      expect(content, contains('<string>--hidden</string>'));
      expect(await service.isEnabled(), isTrue);
    });

    test('Windows 注册表值包含带引号程序路径和 hidden 参数', () async {
      final calls = <({String executable, List<String> arguments})>[];
      final service = desktop_io.DesktopAutoLaunchService(
        platform: TargetPlatform.windows,
        executablePath: r'C:\Program Files\MagicChat\magicchat_client.exe',
        homeDirectory: directory.path,
        processRunner: (executable, arguments) async {
          calls.add((executable: executable, arguments: arguments));
          return ProcessResult(1, 0, '', '');
        },
      );

      await service.setEnabled(true);

      expect(calls.single.executable, 'reg.exe');
      expect(calls.single.arguments, contains('REG_SZ'));
      expect(
        calls.single.arguments,
        contains(r'"C:\Program Files\MagicChat\magicchat_client.exe" --hidden'),
      );
    });

    test('Windows 注册失败会向设置页报告失败', () async {
      final service = desktop_io.DesktopAutoLaunchService(
        platform: TargetPlatform.windows,
        executablePath: r'C:\MagicChat.exe',
        homeDirectory: directory.path,
        processRunner: (_, __) async =>
            ProcessResult(1, 5, '', 'Access denied'),
      );

      await expectLater(
        service.setEnabled(true),
        throwsA(isA<DesktopAutoLaunchException>()),
      );
    });

    test('只有启动项启用且托盘成功时保持隐藏', () {
      expect(isHiddenDesktopLaunch(['--hidden']), isTrue);
      expect(
        shouldKeepDesktopLaunchHidden(
          hiddenRequested: true,
          autoLaunchEnabled: true,
          trayReady: true,
        ),
        isTrue,
      );
      expect(
        shouldKeepDesktopLaunchHidden(
          hiddenRequested: true,
          autoLaunchEnabled: true,
          trayReady: false,
        ),
        isFalse,
      );
      expect(
        shouldKeepDesktopLaunchHidden(
          hiddenRequested: true,
          autoLaunchEnabled: false,
          trayReady: true,
        ),
        isFalse,
      );
    });
  });
}
