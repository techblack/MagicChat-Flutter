import 'dart:async';

import '../../data/auth_service.dart';
import '../../data/repository.dart';

/// 将网络、协议和本地异常转换为可以直接展示给用户的短提示。
///
/// 原始异常可能包含请求地址、资源 ID 或服务端内部细节，不应直接放进
/// SnackBar、空状态和对话框；具体错误仍由诊断日志负责记录。
String userFacingError(Object error, {String fallback = '操作失败，请稍后重试'}) {
  if (error is TimeoutException) return '请求超时，请稍后重试';
  if (error is AuthRequestException) {
    return _statusMessage(error.statusCode, fallback);
  }
  if (error is MagicChatRequestException) {
    return _statusMessage(error.statusCode, fallback);
  }
  if (error is FormatException && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }
  final text = error.toString().toLowerCase();
  if (text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('xmlhttprequest error') ||
      text.contains('network is unreachable')) {
    return '无法连接到服务器，请检查网络后重试';
  }
  return fallback;
}

String _statusMessage(int? statusCode, String fallback) => switch (statusCode) {
      401 => '登录状态已失效，请重新登录',
      403 => '当前账号没有执行此操作的权限',
      404 => '请求的内容不存在或已被移除',
      409 => '操作与当前状态冲突，请刷新后重试',
      429 => '操作过于频繁，请稍后重试',
      500 || 502 || 503 || 504 => '服务器暂时不可用，请稍后重试',
      _ => fallback,
    };
