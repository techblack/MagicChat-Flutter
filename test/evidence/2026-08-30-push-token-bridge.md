# Flutter 推送令牌桥接证据

## 已验证

- iOS `magicchat/push` 原生通道在 APNs 回调后返回 `{provider, platform, environment, token}`，令牌仅保存在本地并按十六进制字符串暴露。
- Android 同一通道显式返回 `null`：Flutter 宿主尚未捆绑 JPush SDK 时安全降级，不伪造 RegistrationID。
- `PushTokenProvider.readDeviceToken()` 校验厂商/平台/环境组合并去除令牌首尾空白；缺少插件或响应非法时返回 `null`。
- Flutter 注册私有 Server grant 时将 `TargetPlatform.iOS` 映射为契约要求的 `ios`（而不是 Dart enum 的 `iOS`）。
- 定向测试：`flutter test test/push_token_provider_test.dart`，11 tests passed。

## 限制

该桥接只提供设备令牌契约。Flutter 当前仍消费原生 `getGrant`，尚未接入
`push-gateway` 的 installation/grant 生命周期；Android JPush SDK 及真实 APNs/JPush
凭据也未加入，因此本证据不代表真实推送可达。
