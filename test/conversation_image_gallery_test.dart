import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/asset_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/messages/conversation_image_gallery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDirectory;

  setUpAll(() async {
    supportDirectory =
        await Directory.systemTemp.createTemp('magicchat-gallery-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProvider,
            (call) async => call.method == 'getApplicationSupportDirectory'
                ? supportDirectory.path
                : null);
  });

  setUp(() async => LocalAssetCache().clearAll());

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('图片消息按序号去重并忽略其他消息类型', () {
    final gallery = buildConversationImageGallery(const [
      ChatMessage(
          id: 'new',
          author: '成员',
          text: '[图片]',
          sequence: 30,
          contentType: 'image',
          rawBody: {'file_id': 'new-file', 'caption': '新图'}),
      ChatMessage(id: 'text', author: '成员', text: '正文', sequence: 20),
      ChatMessage(
          id: 'old',
          author: '成员',
          text: '[图片]',
          sequence: 10,
          contentType: 'image',
          rawBody: {'file_id': 'old-file'}),
    ]);

    expect(gallery.map((item) => item.messageId), ['old', 'new']);
    expect(gallery.map((item) => item.fileId), ['old-file', 'new-file']);
    expect(gallery.last.caption, '新图');
  });

  testWidgets('画廊支持滑动、键盘切换、页码和相邻预取', (tester) async {
    final repository = _GalleryRepository();
    String? forwarded;
    await _pumpGallery(
      tester,
      repository,
      messages: _galleryMessages,
      initialMessageId: 'image-2',
      initialBytes: repository.bytes['file-2'],
      onForward: (messageId) async => forwarded = messageId,
    );

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('第二张图片'), findsOneWidget);

    await tester.drag(find.byKey(const ValueKey('gallery-image-file-2')),
        const Offset(140, 0));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('gallery-image-file-1')));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('第一张图片'), findsOneWidget);
    expect(repository.downloaded, contains('file-1'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('gallery-image-file-2')));
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('转发图片'));
    await tester.pump();
    expect(forwarded, 'image-2');
  });

  testWidgets('到达最旧边界时连续分页寻找更早图片', (tester) async {
    final repository = _GalleryRepository(withOlderPages: true);
    await _pumpGallery(
      tester,
      repository,
      messages: const [
        ChatMessage(
            id: 'image-new',
            author: '成员',
            text: '[图片]',
            sequence: 30,
            contentType: 'image',
            rawBody: {'file_id': 'file-new'}),
      ],
      initialMessageId: 'image-new',
      initialBytes: repository.bytes['file-new'],
      hasOlder: true,
    );

    await tester.tap(find.byKey(const ValueKey('gallery-previous')));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('gallery-image-file-old')));

    expect(repository.beforeSequences, [30, 20]);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('gallery-image-file-old')), findsOneWidget);
  });

  testWidgets('图片失败后可失效单项缓存并重新加载', (tester) async {
    final repository = _GalleryRepository(failFirst: true);
    await _pumpGallery(
      tester,
      repository,
      messages: const [
        ChatMessage(
            id: 'retry-image',
            author: '成员',
            text: '[图片]',
            sequence: 1,
            contentType: 'image',
            rawBody: {'file_id': 'retry-file'}),
      ],
      initialMessageId: 'retry-image',
    );

    await _pumpUntilFound(tester, find.text('图片加载失败'));
    expect(find.text('图片加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('gallery-image-retry-file')));

    expect(repository.downloadAttempts['retry-file'], 2);
    expect(
        find.byKey(const ValueKey('gallery-image-retry-file')), findsOneWidget);
  });
}

Future<void> _pumpGallery(
  WidgetTester tester,
  _GalleryRepository repository, {
  required List<ChatMessage> messages,
  required String initialMessageId,
  bool hasOlder = false,
  Uint8List? initialBytes,
  Future<void> Function(String messageId)? onForward,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: ConversationImageGallery(
      repository: repository,
      conversationId: 'conversation-1',
      messages: messages,
      initialMessageId: initialMessageId,
      hasOlder: hasOlder,
      cacheScope: repository.cacheScope,
      initialBytes: initialBytes,
      onForward: onForward,
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 40 && finder.evaluate().isEmpty; index++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

const _galleryMessages = [
  ChatMessage(
      id: 'image-1',
      author: '成员',
      text: '[图片]',
      sequence: 10,
      contentType: 'image',
      rawBody: {'file_id': 'file-1', 'caption': '第一张图片'}),
  ChatMessage(
      id: 'image-2',
      author: '成员',
      text: '[图片]',
      sequence: 20,
      contentType: 'image',
      rawBody: {'file_id': 'file-2', 'caption': '第二张图片'}),
];

class _GalleryRepository extends DemoRepository {
  _GalleryRepository({this.withOlderPages = false, this.failFirst = false});

  final bool withOlderPages;
  final bool failFirst;
  final beforeSequences = <int?>[];
  final downloaded = <String>[];
  final downloadAttempts = <String, int>{};
  late final MessageCacheScope cacheScope = MessageCacheScope(
      serverUrl: 'gallery-${DateTime.now().microsecondsSinceEpoch}',
      userId: 'test');
  late final Map<String, Uint8List> bytes = {
    'file-1': _png(80, 120, 0xffd64141),
    'file-2': _png(160, 90, 0xff3a76f0),
    'file-new': _png(120, 80, 0xff3a76f0),
    'file-old': _png(80, 120, 0xff4aaa65),
    'retry-file': _png(100, 100, 0xffd68b32),
  };

  @override
  Future<Uri?> attachmentUrl(String fileId) async => null;

  @override
  Future<Uint8List?> downloadAttachment(String fileId) async {
    downloaded.add(fileId);
    final attempt = (downloadAttempts[fileId] ?? 0) + 1;
    downloadAttempts[fileId] = attempt;
    if (failFirst && fileId == 'retry-file' && attempt == 1) return null;
    return bytes[fileId];
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50}) async {
    beforeSequences.add(beforeSeq);
    if (!withOlderPages) return const [];
    if (beforeSeq == 30) {
      return MessagePage(
        messages: const [
          ChatMessage(
              id: 'text-20', author: '成员', text: '中间没有图片', sequence: 20),
        ],
        hasMoreBefore: true,
        hasMoreAfter: false,
        limit: 50,
        newestSeq: 20,
        oldestSeq: 20,
      );
    }
    return MessagePage(
      messages: const [
        ChatMessage(
            id: 'image-old',
            author: '成员',
            text: '[图片]',
            sequence: 10,
            contentType: 'image',
            rawBody: {'file_id': 'file-old'}),
      ],
      hasMoreBefore: false,
      hasMoreAfter: false,
      limit: 50,
      newestSeq: 10,
      oldestSeq: 10,
    );
  }
}

Uint8List _png(int width, int height, int color) {
  final value = image.Image(width: width, height: height);
  image.fill(value,
      color: image.ColorUint32.rgba(
          (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff, 0xff));
  return Uint8List.fromList(image.encodePng(value));
}
