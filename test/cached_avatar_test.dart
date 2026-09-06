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
    LocalAssetCache().writeMemory(key, bytes);
    addTearDown(() => LocalAssetCache().removeMemory(key));

    Widget page(String name) => MaterialApp(
          home:
              CachedAvatar(repository: repository, avatarUri: uri, name: name),
        );

    await tester.pumpWidget(page('Alice'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(page('Alice（更新资料）'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.downloads, 0);
  });

  testWidgets('头像下载和网络加载失败后回退名称首字母', (tester) async {
    final uri = Uri.parse(
        'https://avatar.invalid/${DateTime.now().microsecondsSinceEpoch}.webp');
    await tester.pumpWidget(MaterialApp(
      home: CachedAvatar(
        repository: DemoRepository(),
        avatarUri: uri,
        name: 'Alice',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
