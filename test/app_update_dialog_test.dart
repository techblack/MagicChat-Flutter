import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/update_installer.dart';
import 'package:magicchat_client/data/update_service.dart';
import 'package:magicchat_client/features/settings/app_update_dialog.dart';

void main() {
  testWidgets('Android 更新展示下载进度并允许取消', (tester) async {
    final installer = _PendingInstaller();
    await tester.pumpWidget(_DialogHost(installer: installer));

    await tester.tap(find.text('显示更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('下载安装'), findsOneWidget);

    await tester.tap(find.text('下载安装'));
    await tester.pump();
    expect(find.text('正在更新'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('取消下载'), findsOneWidget);

    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
    expect(installer.cancelled, isTrue);
    expect(find.byType(AppUpdateDialog), findsNothing);
  });

  testWidgets('不支持应用内安装的平台继续打开下载页', (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AppUpdateDialog(
              release: _release,
              installer: AndroidUpdateInstaller(platform: TargetPlatform.linux),
              openDownloadPage: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
          child: const Text('显示更新'),
        ),
      ),
    ));

    await tester.tap(find.text('显示更新'));
    await tester.pumpAndSettle();
    expect(find.text('打开下载页'), findsOneWidget);
    await tester.tap(find.text('打开下载页'));
    await tester.pumpAndSettle();

    expect(opened, Uri.parse(_release.url));
    expect(find.byType(AppUpdateDialog), findsNothing);
  });

  testWidgets('桌面完整包更新显示校验、自动替换和取消入口', (tester) async {
    final installer = _PendingDesktopInstaller();
    await tester.pumpWidget(_DialogHost(installer: installer));

    await tester.tap(find.text('显示更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载安装'));
    await tester.pump();

    expect(find.text('正在下载并校验完整安装包'), findsOneWidget);
    expect(find.text('校验完成后将自动替换当前版本并重启。'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('取消下载'), findsOneWidget);
    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
    expect(installer.cancelled, isTrue);
  });

  testWidgets('活跃文件传输阻断安装并提示完成或取消传输', (tester) async {
    await tester.pumpWidget(_DialogHost(installer: _BlockedInstaller()));

    await tester.tap(find.text('显示更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载安装'));
    await tester.pumpAndSettle();

    expect(find.text('仍有文件正在上传或下载，请等待完成或取消传输后重试'), findsOneWidget);
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    expect(find.text('下载安装'), findsOneWidget);
  });
}

const _release = AppRelease(
    version: '0.4.0', build: 40, url: 'https://example.com/magicchat.apk');

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.installer});

  final UpdateInstaller installer;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  AppUpdateDialog(release: _release, installer: installer),
            ),
            child: const Text('显示更新'),
          ),
        ),
      );
}

class _PendingInstaller extends AndroidUpdateInstaller {
  final _completion = Completer<void>();
  bool cancelled = false;

  @override
  bool get supported => true;

  @override
  Future<void> downloadAndInstall(AppRelease release,
      {required UpdateDownloadProgress onProgress}) {
    onProgress(.42);
    return _completion.future;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_completion.isCompleted) {
      _completion.completeError(const UpdateDownloadCancelled());
    }
  }
}

class _PendingDesktopInstaller implements UpdateInstaller {
  final _completion = Completer<void>();
  bool cancelled = false;

  @override
  bool get supported => true;

  @override
  String get progressLabel => '正在下载并校验完整安装包';

  @override
  String get completionHint => '校验完成后将自动替换当前版本并重启。';

  @override
  Future<void> downloadAndInstall(AppRelease release,
      {required UpdateDownloadProgress onProgress}) {
    onProgress(.42);
    return _completion.future;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_completion.isCompleted) {
      _completion.completeError(const UpdateDownloadCancelled());
    }
  }
}

class _BlockedInstaller implements UpdateInstaller {
  @override
  bool get supported => true;

  @override
  String get progressLabel => '正在下载并校验完整安装包';

  @override
  String get completionHint => '校验完成后将自动替换当前版本并重启。';

  @override
  Future<void> downloadAndInstall(AppRelease release,
          {required UpdateDownloadProgress onProgress}) =>
      throw const UpdateInstallBlockedByActiveTransfers();

  @override
  Future<void> cancel() async {}
}
