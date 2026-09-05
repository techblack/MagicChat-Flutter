import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/asset_cache_store.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/features/shared/cached_avatar.dart';

void main() {
  testWidgets('头像在页面切换时复用进程缓存，不重复请求', (tester) async {
    final repository = _AvatarCacheRepository();
    final uri = Uri.parse(
        'https://avatar.example.com/cache-${DateTime.now().microsecondsSinceEpoch}.png');
    final key = 'avatar|$uri';
    final bytes = _avatarBytes();
    await LocalAssetCache().write(key, bytes);
    addTearDown(() => LocalAssetCache().remove(key));

    Widget page(String name) => MaterialApp(
          home:
              CachedAvatar(repository: repository, avatarUri: uri, name: name),
        );

    await tester.pumpWidget(page('Alice'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('Alice（更新资料）'));
    await tester.pumpAndSettle();

    expect(repository.downloads, 0);
  });

  testWidgets('同一头像并发出现时只发起一次下载', (tester) async {
    final repository = _AvatarCacheRepository();
    final uri = Uri.parse(
        'https://avatar.example.com/inflight-${DateTime.now().microsecondsSinceEpoch}.png');
    final key = 'avatar|$uri';
    addTearDown(() => LocalAssetCache().remove(key));

    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      CachedAvatar(repository: repository, avatarUri: uri, name: 'Alice'),
      CachedAvatar(repository: repository, avatarUri: uri, name: 'Alice'),
    ])));
    await tester.pumpAndSettle();

    expect(repository.downloads, 1);
  });
}

Uint8List _avatarBytes() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 1, height: 1)));

class _AvatarCacheRepository extends DemoRepository {
  var downloads = 0;

  @override
  Future<Uint8List?> downloadResource(Uri uri) async {
    downloads++;
    return _avatarBytes();
  }
}
