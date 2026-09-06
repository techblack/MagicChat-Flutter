import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/desktop_screenshot.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/settings/desktop_screenshot_shortcut_dialog.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('选择区域截图后预览并进入现有图片发送队列', (tester) async {
    final directory = Directory.systemTemp.createTempSync('shot-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final repository = _ScreenshotRepository();
    final capture = _CaptureBackend();
    final controller = DesktopScreenshotController(
      captureBackend: capture,
      hotKeyBackend: _HotKeyBackend(),
      platform: TargetPlatform.linux,
      temporaryDirectoryPath: () async => directory.path,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: repository,
          conversationId: 'conversation-1',
          screenshotController: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('截图'));
    await tester.pumpAndSettle();
    expect(find.text('截取整个屏幕'), findsOneWidget);
    await tester.tap(find.text('选择区域截图'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(capture.mode, DesktopScreenshotMode.region);
    expect(find.text('发送截图'), findsOneWidget);
    expect(find.byKey(const ValueKey('screenshot-preview-metadata')),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(repository.upload?.mimeType, 'image/png');
    expect(repository.upload?.bytes, _pngBytes);
    expect(repository.conversationId, 'conversation-1');
  });

  testWidgets('只读会话禁用截图入口', (tester) async {
    final store = RealtimeStore()
      ..conversations['conversation-1'] = const ChatConversation(
          id: 'conversation-1', title: '只读会话', canSend: false);
    final controller = DesktopScreenshotController(
      captureBackend: _CaptureBackend(),
      hotKeyBackend: _HotKeyBackend(),
      platform: TargetPlatform.linux,
    );
    addTearDown(controller.dispose);
    Widget page(int requestToken) => MaterialApp(
          home: Scaffold(
            body: ConversationView(
              repository: _ScreenshotRepository(),
              realtimeStore: store,
              conversationId: 'conversation-1',
              screenshotController: controller,
              screenshotRequestToken: requestToken,
            ),
          ),
        );
    await tester.pumpWidget(page(0));
    await tester.pumpAndSettle();

    final button = tester.widget<PopupMenuButton<DesktopScreenshotMode>>(
        find.byWidgetPredicate((widget) =>
            widget is PopupMenuButton<DesktopScreenshotMode> &&
            widget.tooltip == '截图'));
    expect(button.enabled, isFalse);

    await tester.pumpWidget(page(1));
    await tester.pump();
    expect(find.text('当前会话为只读，无法发送截图'), findsOneWidget);
  });

  testWidgets('截图权限被拒绝时显示系统设置引导', (tester) async {
    final directory = Directory.systemTemp.createTempSync('shot-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final capture = _CaptureBackend(accessAllowed: false);
    final controller = DesktopScreenshotController(
      captureBackend: capture,
      hotKeyBackend: _HotKeyBackend(),
      platform: TargetPlatform.macOS,
      temporaryDirectoryPath: () async => directory.path,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: _ScreenshotRepository(),
          conversationId: 'conversation-1',
          screenshotController: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('截图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择区域截图'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('需要屏幕录制权限'), findsOneWidget);
    await tester.tap(find.text('打开系统设置'));
    await tester.pumpAndSettle();
    expect(capture.settingsRequests, 1);
  });

  testWidgets('截图快捷键可重新录制', (tester) async {
    final initial =
        DesktopScreenshotShortcut.defaultFor(TargetPlatform.windows);
    DesktopScreenshotShortcut? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            result = await showDialog<DesktopScreenshotShortcut>(
              context: context,
              builder: (_) => DesktopScreenshotShortcutDialog(
                initial: initial,
                platform: TargetPlatform.windows,
              ),
            );
          },
          child: const Text('打开'),
        );
      }),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS,
        physicalKey: PhysicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Ctrl+Shift+S'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result?.keyCode, PhysicalKeyboardKey.keyS.usbHidUsage);
    expect(result?.modifiers, {
      DesktopShortcutModifier.control,
      DesktopShortcutModifier.shift,
    });
  });

  testWidgets('设置页可禁用并重新启用截图快捷键', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initial = DesktopScreenshotShortcut.defaultFor(TargetPlatform.linux);
    final changes = <DesktopScreenshotShortcut>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsPage(
          repository: DemoRepository(),
          serverUrl: 'https://chat.example.com',
          screenshotShortcut: initial,
          onScreenshotShortcutChanged: (shortcut) async {
            changes.add(shortcut);
            return true;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '桌面截图快捷键');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(changes.single.enabled, isFalse);
    expect(find.text('已禁用'), findsOneWidget);
    expect(find.text('修改截图快捷键'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _ScreenshotRepository extends DemoRepository {
  String? conversationId;
  AttachmentUpload? upload;

  @override
  Future<void> sendImage(String conversationId, AttachmentUpload upload,
      {String caption = '',
      String? replyToMessageId,
      String? clientMessageId}) async {
    this.conversationId = conversationId;
    this.upload = upload;
  }
}

class _CaptureBackend implements DesktopScreenshotCaptureBackend {
  _CaptureBackend({this.accessAllowed = true});

  bool accessAllowed;
  int settingsRequests = 0;
  DesktopScreenshotMode? mode;

  @override
  Future<CapturedScreenshot?> capture(
      DesktopScreenshotMode mode, String imagePath) async {
    this.mode = mode;
    File(imagePath).writeAsBytesSync(_pngBytes);
    return CapturedScreenshot(
        bytes: _pngBytes, width: 1, height: 1, fileName: 'MagicChat-test.png');
  }

  @override
  Future<bool> isAccessAllowed() async => accessAllowed;

  @override
  Future<void> requestAccess({required bool openSettingsOnly}) async {
    if (openSettingsOnly) settingsRequests++;
  }
}

class _HotKeyBackend implements DesktopScreenshotHotKeyBackend {
  @override
  Future<void> register(
      DesktopScreenshotShortcut shortcut, AsyncCallback onTriggered) async {}

  @override
  Future<void> unregister() async {}
}

final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
