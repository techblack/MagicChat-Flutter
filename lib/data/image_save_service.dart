import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

enum ImageSaveDestination { photoLibrary, download, file }

class ImageSaveResult {
  const ImageSaveResult({required this.destination, required this.saved});

  final ImageSaveDestination destination;
  final bool saved;

  String get message => switch (destination) {
        ImageSaveDestination.photoLibrary => '图片已保存到系统相册',
        ImageSaveDestination.download => '图片已下载',
        ImageSaveDestination.file => '图片已保存',
      };
}

enum ImageSaveFailure {
  permissionDenied,
  notEnoughSpace,
  unsupportedFormat,
  unavailable,
}

class ImageSaveException implements Exception {
  const ImageSaveException(this.failure);

  final ImageSaveFailure failure;

  String get message => switch (failure) {
        ImageSaveFailure.permissionDenied => '没有保存图片到系统相册的权限，请在系统设置中允许访问',
        ImageSaveFailure.notEnoughSpace => '设备存储空间不足',
        ImageSaveFailure.unsupportedFormat => '当前图片格式不支持保存',
        ImageSaveFailure.unavailable => '当前平台暂时无法保存图片',
      };

  @override
  String toString() => message;
}

typedef ImageGalleryAccess = Future<bool> Function();
typedef ImageGalleryWriter = Future<void> Function(
    Uint8List bytes, String name);
typedef ImageFileWriter = Future<String?> Function(
    Uint8List bytes, String fileName);

class ImageSaveService {
  const ImageSaveService({
    ImageGalleryAccess? hasGalleryAccess,
    ImageGalleryAccess? requestGalleryAccess,
    ImageGalleryWriter? galleryWriter,
    ImageFileWriter? fileWriter,
  })  : _hasGalleryAccess = hasGalleryAccess,
        _requestGalleryAccess = requestGalleryAccess,
        _galleryWriter = galleryWriter,
        _fileWriter = fileWriter;

  final ImageGalleryAccess? _hasGalleryAccess;
  final ImageGalleryAccess? _requestGalleryAccess;
  final ImageGalleryWriter? _galleryWriter;
  final ImageFileWriter? _fileWriter;

  Future<ImageSaveResult> save(
    Uint8List bytes, {
    required String suggestedName,
    required int fallbackIndex,
    bool? isWeb,
    TargetPlatform? platform,
  }) async {
    if (bytes.isEmpty) {
      throw const ImageSaveException(ImageSaveFailure.unsupportedFormat);
    }
    final web = isWeb ?? kIsWeb;
    final target = platform ?? defaultTargetPlatform;
    final fileName = imageSaveFileName(
      bytes,
      suggestedName: suggestedName,
      fallbackIndex: fallbackIndex,
    );
    if (web) {
      await (_fileWriter ?? _saveFile)(bytes, fileName);
      return const ImageSaveResult(
          destination: ImageSaveDestination.download, saved: true);
    }
    if (target == TargetPlatform.android || target == TargetPlatform.iOS) {
      return _saveToPhotoLibrary(bytes, fileName);
    }
    if (target == TargetPlatform.macOS ||
        target == TargetPlatform.windows ||
        target == TargetPlatform.linux) {
      final path = await (_fileWriter ?? _saveFile)(bytes, fileName);
      return ImageSaveResult(
          destination: ImageSaveDestination.file, saved: path != null);
    }
    throw const ImageSaveException(ImageSaveFailure.unavailable);
  }

  Future<ImageSaveResult> _saveToPhotoLibrary(
      Uint8List bytes, String fileName) async {
    try {
      final hasAccess = await (_hasGalleryAccess ?? Gal.hasAccess)();
      if (!hasAccess) {
        final granted = await (_requestGalleryAccess ?? Gal.requestAccess)();
        if (!granted) {
          throw const ImageSaveException(ImageSaveFailure.permissionDenied);
        }
      }
      await (_galleryWriter ?? _writeGallery)(
          bytes, fileName.substring(0, fileName.lastIndexOf('.')));
      return const ImageSaveResult(
          destination: ImageSaveDestination.photoLibrary, saved: true);
    } on GalException catch (error) {
      throw ImageSaveException(switch (error.type) {
        GalExceptionType.accessDenied => ImageSaveFailure.permissionDenied,
        GalExceptionType.notEnoughSpace => ImageSaveFailure.notEnoughSpace,
        GalExceptionType.notSupportedFormat =>
          ImageSaveFailure.unsupportedFormat,
        GalExceptionType.unexpected => ImageSaveFailure.unavailable,
      });
    }
  }

  Future<void> _writeGallery(Uint8List bytes, String name) =>
      Gal.putImageBytes(bytes, name: name);

  Future<String?> _saveFile(Uint8List bytes, String fileName) =>
      FilePicker.saveFile(
        dialogTitle: '保存图片',
        fileName: fileName,
        bytes: bytes,
      );
}

String imageSaveActionLabel({bool? isWeb, TargetPlatform? platform}) {
  if (isWeb ?? kIsWeb) return '下载图片';
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.android || target == TargetPlatform.iOS
      ? '保存到系统相册'
      : '保存图片';
}

String imageSaveFileName(
  Uint8List bytes, {
  required String suggestedName,
  required int fallbackIndex,
}) {
  final normalized = suggestedName.trim().split(RegExp(r'[/\\]')).last;
  final dot = normalized.lastIndexOf('.');
  final base = (dot > 0 ? normalized.substring(0, dot) : normalized).trim();
  final fallback = 'MagicChat-image-$fallbackIndex';
  final suggestedExtension =
      dot > 0 ? normalized.substring(dot + 1).toLowerCase() : '';
  final extension = _imageExtension(bytes) ??
      (const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(suggestedExtension)
          ? suggestedExtension
          : 'jpg');
  return '${base.isEmpty ? fallback : base}.$extension';
}

String? _imageExtension(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpg';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}
