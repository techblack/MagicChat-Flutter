import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/asset_cache_store.dart';
import 'package:magicchat_client/data/message_cache_store.dart';
import 'package:magicchat_client/data/storage_service.dart';
import 'package:magicchat_client/data/storage_service_stub.dart' as web_storage;
import 'package:magicchat_client/features/settings/storage_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('按媒体与离线消息分别统计并清理实际缓存目录', () async {
    final root = await Directory.systemTemp.createTemp('magicchat-storage-');
    addTearDown(() => root.delete(recursive: true));
    final temporary = Directory('${root.path}/temporary')..createSync();
    final support = Directory('${root.path}/support')..createSync();
    final assets = Directory('${support.path}/${LocalAssetCache.directoryName}')
      ..createSync();
    final messages = Directory('${support.path}/message-cache')..createSync();
    File('${temporary.path}/preview.bin').writeAsBytesSync(List.filled(512, 1));
    File('${assets.path}/attachment.bin')
        .writeAsBytesSync(List.filled(1024, 2));
    File('${messages.path}/magicchat_messages_test.sqlite3')
        .writeAsBytesSync(List.filled(2048, 3));
    final service = StorageService(
      messageCacheStore: MessageCacheStore(databaseDirectory: messages.path),
      temporaryDirectoryPath: temporary.path,
      applicationSupportDirectoryPath: support.path,
    );

    var info = await service.inspect();
    expect(info.mediaBytes, 1536);
    expect(info.messageBytes, 2048);
    expect(info.formattedMedia, '1.5 KB');

    await service.clear(StoragePart.media);
    info = await service.inspect();
    expect(info.mediaBytes, 0);
    expect(info.messageBytes, 2048);

    await service.clear(StoragePart.messages);
    info = await service.inspect();
    expect(info.messageBytes, 0);
  });

  test('Web 持久化缓存按媒体与消息分类统计', () async {
    SharedPreferences.setMockInitialValues({
      '${LocalAssetCache.keyPrefix}asset': 'YWJj',
      '${MessageCacheStore.keyPrefix}messages': '[{"id":"m1"}]',
      'unrelated': 'ignored',
    });

    final info = await web_storage.StorageService().inspect();
    expect(info.mediaBytes, greaterThan(0));
    expect(info.messageBytes, greaterThan(info.mediaBytes));
    expect(info.totalBytes, info.mediaBytes + info.messageBytes);
  });

  testWidgets('存储页展示分项并在确认后单独清理', (tester) async {
    final service = _FakeStorageService();
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('storage-management-golden'),
      child: SizedBox(
        width: 600,
        height: 800,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: StorageManagementPage(service: service)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('媒体与文件'), findsOneWidget);
    expect(find.text('离线消息'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.text('2.0 MB'), findsNWidgets(2));
    await expectLater(
      find.byKey(const ValueKey('storage-management-golden')),
      matchesGoldenFile('evidence/storage_management.png'),
    );

    await tester.tap(find.text('清理媒体与文件'));
    await tester.pumpAndSettle();
    expect(find.text('清理媒体与文件？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '清理'));
    await tester.pumpAndSettle();

    expect(service.cleared, [StoragePart.media]);
    expect(find.text('0 B'), findsOneWidget);
  });
}

class _FakeStorageService extends StorageService {
  StorageInfo info =
      const StorageInfo(mediaBytes: 1536, messageBytes: 2 * 1024 * 1024);
  final cleared = <StoragePart>[];

  @override
  Future<StorageInfo> inspect() async => info;

  @override
  Future<void> clear(StoragePart part) async {
    cleared.add(part);
    info = StorageInfo(
      mediaBytes: part == StoragePart.media || part == StoragePart.all
          ? 0
          : info.mediaBytes,
      messageBytes: part == StoragePart.messages || part == StoragePart.all
          ? 0
          : info.messageBytes,
    );
  }
}
