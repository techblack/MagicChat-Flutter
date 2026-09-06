import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:magicchat_client/data/image_save_service.dart';

void main() {
  final png =
      Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

  test('Android 和 iOS 请求权限后将真实字节写入系统相册', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      var requested = 0;
      Uint8List? savedBytes;
      String? savedName;
      final service = ImageSaveService(
        hasGalleryAccess: () async => false,
        requestGalleryAccess: () async {
          requested++;
          return true;
        },
        galleryWriter: (bytes, name) async {
          savedBytes = bytes;
          savedName = name;
        },
      );

      final result = await service.save(
        png,
        suggestedName: '现场照片.jpg',
        fallbackIndex: 1,
        isWeb: false,
        platform: platform,
      );

      expect(requested, 1);
      expect(savedBytes, png);
      expect(savedName, '现场照片');
      expect(result.destination, ImageSaveDestination.photoLibrary);
      expect(result.saved, isTrue);
    }
  });

  test('移动端相册权限拒绝和原生错误转为可读原因', () async {
    final denied = ImageSaveService(
      hasGalleryAccess: () async => false,
      requestGalleryAccess: () async => false,
    );
    await expectLater(
      denied.save(png,
          suggestedName: '',
          fallbackIndex: 1,
          isWeb: false,
          platform: TargetPlatform.android),
      throwsA(isA<ImageSaveException>()
          .having((error) => error.message, 'message', contains('系统设置'))),
    );

    final noSpace = ImageSaveService(
      hasGalleryAccess: () async => true,
      galleryWriter: (_, __) async => throw GalException(
        type: GalExceptionType.notEnoughSpace,
        platformException: PlatformException(code: 'NOT_ENOUGH_SPACE'),
        stackTrace: StackTrace.current,
      ),
    );
    await expectLater(
      noSpace.save(png,
          suggestedName: '',
          fallbackIndex: 1,
          isWeb: false,
          platform: TargetPlatform.iOS),
      throwsA(isA<ImageSaveException>().having((error) => error.failure,
          'failure', ImageSaveFailure.notEnoughSpace)),
    );
  });

  test('Web 下载与桌面文件保存使用各自成功语义', () async {
    final writes = <String>[];
    final service = ImageSaveService(
      fileWriter: (_, fileName) async {
        writes.add(fileName);
        return null;
      },
    );

    final web = await service.save(
      png,
      suggestedName: '',
      fallbackIndex: 3,
      isWeb: true,
      platform: TargetPlatform.android,
    );
    expect(web.destination, ImageSaveDestination.download);
    expect(web.saved, isTrue);
    expect(writes.single, 'MagicChat-image-3.png');

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final desktop = await service.save(
        png,
        suggestedName: '图片.png',
        fallbackIndex: 1,
        isWeb: false,
        platform: platform,
      );
      expect(desktop.destination, ImageSaveDestination.file);
      expect(desktop.saved, isFalse);
    }
  });

  test('操作文案和扩展名匹配平台与真实图片格式', () {
    expect(imageSaveActionLabel(isWeb: true), '下载图片');
    expect(imageSaveActionLabel(isWeb: false, platform: TargetPlatform.android),
        '保存到系统相册');
    expect(imageSaveActionLabel(isWeb: false, platform: TargetPlatform.windows),
        '保存图片');
    expect(imageSaveFileName(png, suggestedName: '../错误.jpg', fallbackIndex: 1),
        '错误.png');
    expect(
        imageSaveFileName(Uint8List(1),
            suggestedName: '../图片.exe', fallbackIndex: 2),
        '图片.jpg');
  });
}
