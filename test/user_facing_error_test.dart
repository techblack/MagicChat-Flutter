import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/features/shared/user_facing_error.dart';

void main() {
  test('网络和服务端状态转换为用户可理解的提示', () {
    expect(userFacingError(TimeoutException('token=secret')), '请求超时，请稍后重试');
    expect(
        userFacingError(const MagicChatRequestException(
            statusCode: 403, message: 'user-id=internal')),
        '当前账号没有执行此操作的权限');
    expect(userFacingError(Exception('https://chat.example/api/users/user-1')),
        '操作失败，请稍后重试');
  });

  test('保留安全的格式校验提示', () {
    expect(userFacingError(const FormatException('请输入服务器地址')), '请输入服务器地址');
  });
}
