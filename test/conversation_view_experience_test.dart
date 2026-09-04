import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/asset_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/data/realtime_store.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('双击消息打开可选择复制的独立详情', (tester) async {
    await _pumpConversation(tester, _ExperienceRepository());

    final message = find.text('可以自由选择复制的正文');
    await tester.tap(message);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(message);
    await tester.pumpAndSettle();

    expect(find.text('消息详情'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('message-details-content')), findsOneWidget);
    expect(
        tester
            .widget<SelectableText>(
                find.byKey(const ValueKey('message-details-content')))
            .data,
        '可以自由选择复制的正文');
  });

  testWidgets('消息左滑进入引用回复且消息不被删除', (tester) async {
    await _pumpConversation(tester, _ExperienceRepository());

    await tester.drag(find.byKey(const ValueKey('message-swipe-text-1')),
        const Offset(-260, 0));
    await tester.pumpAndSettle();

    expect(find.text('回复 Alice：可以自由选择复制的正文'), findsOneWidget);
    expect(find.text('可以自由选择复制的正文'), findsOneWidget);
  });

  testWidgets('引用回复显示对应消息和联系人名称，不显示原始 ID', (tester) async {
    await _pumpConversation(tester, _ReplyReferenceRepository());

    expect(find.text('回复 Bob：原消息提到 @Alice'), findsOneWidget);
    expect(find.text('quoted-message'), findsNothing);
    expect(find.textContaining('{(@user/alice)}'), findsNothing);
  });

  testWidgets('图片消息只显示图片并按原始比例调整尺寸', (tester) async {
    final repository = _ImageRepository()..primeCache();
    await _pumpConversation(tester, repository, settle: false);
    for (var i = 0;
        i < 20 &&
            find
                .byKey(const ValueKey('conversation-image-image-wide'))
                .evaluate()
                .isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('[图片]'), findsNothing);
    final wide = tester
        .getSize(find.byKey(const ValueKey('conversation-image-image-wide')));
    final tall = tester
        .getSize(find.byKey(const ValueKey('conversation-image-image-tall')));
    expect(wide.aspectRatio, closeTo(2, .01));
    expect(tall.aspectRatio, closeTo(.5, .01));
    expect(wide.width, greaterThan(tall.width));
    expect(wide.height, lessThan(tall.height));
  });

  testWidgets('短消息气泡比长消息更窄且输入区不应用顶部安全间距', (tester) async {
    await _pumpConversation(tester, _BubbleRepository());

    final shortBubble = tester
        .getSize(find.byKey(const ValueKey('message-bubble-short-message')));
    final longBubble = tester
        .getSize(find.byKey(const ValueKey('message-bubble-long-message')));
    expect(shortBubble.width, lessThan(longBubble.width));
    expect(longBubble.width, lessThanOrEqualTo(600));
    expect(
        tester
            .widget<SafeArea>(
                find.byKey(const ValueKey('message-composer-safe-area')))
            .top,
        isFalse);
  });

  testWidgets('滚动到顶部加载旧消息时显示短暂进度动画', (tester) async {
    final repository = _OlderMessagesRepository();
    await _pumpConversation(tester, repository);

    await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
    await tester.pump();

    expect(repository.olderRequested, isTrue);
    expect(
        find.byKey(const ValueKey('older-messages-loading')), findsOneWidget);

    repository.older.complete([
      const ChatMessage(
          id: 'older-50', sequence: 50, author: 'Alice', text: '更早的消息'),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('older-messages-loading')), findsNothing);
    expect(find.text('更早的消息'), findsOneWidget);
  });

  testWidgets('浏览历史时自己的实时消息不计入新消息提示', (tester) async {
    final store = RealtimeStore()..setCurrentUserId('me');
    store.conversations['conversation-1'] = const ChatConversation(
        id: 'conversation-1', title: '测试会话', type: 'group');
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConversationView(
                repository: _OlderMessagesRepository(),
                realtimeStore: store,
                conversationId: 'conversation-1'))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pump();

    store.apply({
      'cursor': 1,
      'event': 'message.created',
      'payload': {
        'id': 'mine-101',
        'conversation_id': 'conversation-1',
        'seq': 101,
        'sender': {'id': 'me', 'name': '我'},
        'body': {'type': 'text', 'content': '自己发送'}
      }
    });
    await tester.pump();

    expect(find.text('新消息 1'), findsNothing);
  });
}

Future<void> _pumpConversation(
    WidgetTester tester, MagicChatRepository repository,
    {bool settle = true}) async {
  await tester.binding.setSurfaceSize(const Size(600, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ConversationView(
              repository: repository, conversationId: 'conversation-1'))));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _ExperienceRepository extends DemoRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'text-1',
            conversationId: 'conversation-1',
            sequence: 1,
            authorId: 'alice',
            author: 'Alice',
            text: '可以自由选择复制的正文'),
      ];

  @override
  Future<List<ChatConversation>> conversations() async => const [
        ChatConversation(id: 'conversation-1', title: '测试会话'),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'alice', name: 'Alice'),
      ];
}

class _ImageRepository extends _ExperienceRepository {
  final Map<String, Uint8List> _images = {
    'image-wide': Uint8List.fromList(
        image.encodePng(image.Image(width: 400, height: 200))),
    'image-tall': Uint8List.fromList(
        image.encodePng(image.Image(width: 200, height: 400))),
  };

  void primeCache() {
    for (final entry in _images.entries) {
      unawaited(LocalAssetCache()
          .write('attachment|${entry.key}', entry.value)
          .catchError((_) {}));
    }
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'image-wide',
            conversationId: 'conversation-1',
            sequence: 1,
            contentType: 'image',
            rawBody: {'type': 'image', 'file_id': 'image-wide'},
            author: '我',
            text: '[图片]',
            mine: true),
        ChatMessage(
            id: 'image-tall',
            conversationId: 'conversation-1',
            sequence: 2,
            contentType: 'image',
            rawBody: {'type': 'image', 'file_id': 'image-tall'},
            author: '我',
            text: '[图片]',
            mine: true),
      ];

  @override
  Future<Uint8List?> downloadAttachment(String fileId) async => _images[fileId];
}

class _ReplyReferenceRepository extends _ExperienceRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'quoted-message',
            conversationId: 'conversation-1',
            sequence: 1,
            authorId: 'bob',
            author: 'bob',
            text: '原消息提到 {(@user/alice)}'),
        ChatMessage(
            id: 'reply-message',
            conversationId: 'conversation-1',
            sequence: 2,
            authorId: 'alice',
            author: 'alice',
            text: '收到',
            replyTo: MessageReply(
                id: 'quoted-message',
                authorId: 'bob',
                author: 'bob',
                text: 'quoted-message')),
      ];

  @override
  Future<List<Contact>> contacts({String keyword = ''}) async => const [
        Contact(id: 'alice', name: 'Alice'),
        Contact(id: 'bob', name: 'Bob'),
      ];
}

class _BubbleRepository extends _ExperienceRepository {
  @override
  Future<List<ChatMessage>> messages(String conversationId,
          {int? beforeSeq, int limit = 50}) async =>
      const [
        ChatMessage(
            id: 'short-message',
            conversationId: 'conversation-1',
            sequence: 1,
            author: '我',
            text: '好',
            mine: true),
        ChatMessage(
            id: 'long-message',
            conversationId: 'conversation-1',
            sequence: 2,
            author: '我',
            text: '这是一条明显更长的消息，用来验证气泡会根据内容长度自动调整宽度，达到上限后再自然换行。',
            mine: true),
      ];
}

class _OlderMessagesRepository extends _ExperienceRepository {
  final older = Completer<List<ChatMessage>>();
  bool olderRequested = false;

  @override
  Future<List<ChatMessage>> messages(String conversationId,
      {int? beforeSeq, int limit = 50}) {
    if (beforeSeq != null) {
      olderRequested = true;
      return older.future;
    }
    return Future.value(List.generate(
        50,
        (index) => ChatMessage(
            id: 'message-${index + 51}',
            conversationId: 'conversation-1',
            sequence: index + 51,
            author: 'Alice',
            text: '历史消息 ${index + 51}')));
  }
}
