# Flutter 推送令牌桥接证据

## 已验证

- iOS `magicchat/push` 原生通道在 APNs 回调后返回 `{provider, platform, environment, token}`，令牌仅保存在本地并按十六进制字符串暴露。
- Android 同一通道显式返回 `null`：Flutter 宿主尚未捆绑 JPush SDK 时安全降级，不伪造 RegistrationID。
- `PushTokenProvider.readDeviceToken()` 校验厂商/平台/环境组合并去除令牌首尾空白；缺少插件或响应非法时返回 `null`。
- Flutter 注册私有 Server grant 时将 `TargetPlatform.iOS` 映射为契约要求的 `ios`（而不是 Dart enum 的 `iOS`），并在设备令牌可用时先完成公共 Gateway installation/grant 生命周期。
- 定向测试：`flutter test test/push_token_provider_test.dart`，12 tests passed。

## 限制

Android 同时仍显式返回 `null`，未配置 JPush 时不会伪造 RegistrationID；真实
APNs/JPush 凭据和 Android JPush SDK 仍需按发布环境配置，因此本证据不代表所有平台
真实推送均可达。
