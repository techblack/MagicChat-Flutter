import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/desktop_screenshot.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/domain/screenshot_annotations.dart';
import 'package:magicchat_client/features/messages/screenshot_annotation_dialog.dart';
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
    expect(find.text('矩形'), findsOneWidget);
    expect(find.text('箭头'), findsOneWidget);
    expect(find.text('画笔'), findsOneWidget);
    expect(find.text('文字'), findsOneWidget);
    for (final color in screenshotAnnotationColors) {
      expect(find.byTooltip('使用颜色 #${color.toRadixString(16).substring(2)}'),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('screenshot-preview-metadata')),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(repository.upload?.mimeType, 'image/png');
    expect(repository.upload?.bytes, _pngBytes);
    expect(repository.conversationId, 'conversation-1');
  });

  testWidgets('截图可添加矩形标注并撤销重做后发送', (tester) async {
    final directory = Directory.systemTemp.createTempSync('shot-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = image.Image(width: 160, height: 90, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(255, 255, 255, 255));
    final sourceBytes = Uint8List.fromList(image.encodePng(source));
    final repository = _ScreenshotRepository();
    final controller = DesktopScreenshotController(
      captureBackend:
          _CaptureBackend(bytes: sourceBytes, width: 160, height: 90),
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
    await tester.tap(find.text('选择区域截图'));
    await tester.pump(const Duration(milliseconds: 100));
    final canvas = tester
        .getRect(find.byKey(const ValueKey('screenshot-annotation-canvas')));
    await tester.dragFrom(
        canvas.topLeft + const Offset(20, 20), const Offset(100, 45));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '箭头'));
    await tester.pump();
    await tester.dragFrom(
        canvas.topLeft + const Offset(40, 70), const Offset(110, -25));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '画笔'));
    await tester.pump();
    await tester.dragFrom(
        canvas.topLeft + const Offset(80, 30), const Offset(70, 35));
    await tester.pump();
    final undo =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo));
    expect(undo.onPressed, isNotNull);
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    final redo =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo));
    expect(redo.onPressed, isNotNull);
    await tester.tap(find.byTooltip('重做'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    for (var attempt = 0;
        attempt < 20 && repository.upload == null;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const ValueKey('screenshot-annotation-error')),
        findsNothing);
    expect(find.text('发送截图'), findsNothing);
    expect(repository.upload, isNotNull);
    expect(repository.upload?.bytes, isNot(equals(sourceBytes)));
    final output = image.decodePng(repository.upload!.bytes!)!;
    expect(output.width, 160);
    expect(output.height, 90);
    expect(_coloredPixelCount(output), greaterThan(0));
  });

  testWidgets('截图可在点击位置添加中文文字并撤销重做', (tester) async {
    final source = image.Image(width: 160, height: 90, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(255, 255, 255, 255));
    await tester.pumpWidget(MaterialApp(
      home: ScreenshotAnnotationDialog(
        screenshot: CapturedScreenshot(
          bytes: Uint8List.fromList(image.encodePng(source)),
          width: 160,
          height: 90,
          fileName: 'text.png',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '文字'));
    await tester.pump();
    final canvas = tester
        .getRect(find.byKey(const ValueKey('screenshot-annotation-canvas')));
    await tester.tapAt(canvas.topLeft + const Offset(30, 25));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        find.byKey(const ValueKey('screenshot-text-input')), '重点');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 300));

    final annotationPaint = find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is ScreenshotAnnotationPainter);
    ScreenshotAnnotationPainter painter() =>
        tester.widget<CustomPaint>(annotationPaint).painter!
            as ScreenshotAnnotationPainter;
    expect(
        painter().annotations.whereType<ScreenshotTextAnnotation>().single.text,
        '重点');
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    expect(
        painter().annotations.whereType<ScreenshotTextAnnotation>(), isEmpty);
    await tester.tap(find.byTooltip('重做'));
    await tester.pump();
    expect(painter().annotations.whereType<ScreenshotTextAnnotation>(),
        hasLength(1));
  });

  testWidgets('取消截图标注不进入发送队列', (tester) async {
    final directory = Directory.systemTemp.createTempSync('shot-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final repository = _ScreenshotRepository();
    final controller = DesktopScreenshotController(
      captureBackend: _CaptureBackend(),
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
    await tester.tap(find.text('截取整个屏幕'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.upload, isNull);
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
  _CaptureBackend({
    this.accessAllowed = true,
    Uint8List? bytes,
    this.width = 1,
    this.height = 1,
  }) : bytes = bytes ?? _pngBytes;

  bool accessAllowed;
  final Uint8List bytes;
  final int width;
  final int height;
  int settingsRequests = 0;
  DesktopScreenshotMode? mode;

  @override
  Future<CapturedScreenshot?> capture(
      DesktopScreenshotMode mode, String imagePath) async {
    this.mode = mode;
    File(imagePath).writeAsBytesSync(bytes);
    return CapturedScreenshot(
        bytes: bytes,
        width: width,
        height: height,
        fileName: 'MagicChat-test.png');
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

int _coloredPixelCount(image.Image value) {
  var count = 0;
  for (final pixel in value) {
    if (pixel.r.toInt() != 255 ||
        pixel.g.toInt() != 255 ||
        pixel.b.toInt() != 255) {
      count++;
    }
  }
  return count;
}
