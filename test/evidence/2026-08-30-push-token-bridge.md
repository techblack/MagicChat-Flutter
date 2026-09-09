# Flutter 推送令牌桥接证据

## 已验证

- iOS `magicchat/push` 原生通道在 APNs 回调后返回 `{provider, platform, environment, token}`，令牌仅保存在本地并按十六进制字符串暴露。
- Android 构建默认携带官方公开 JPush AppKey（`d7fa4b31dd21064e095d29d5`），`JPUSH_APP_KEY` 可覆盖为独立开发/测试应用；在用户明确同意前仍显式返回 `null`，不会伪造或读取 RegistrationID，同意后通过同一通道返回生产 RegistrationID。
- `PushTokenProvider.readDeviceToken()` 校验厂商/平台/环境组合并去除令牌首尾空白；缺少插件或响应非法时返回 `null`。
- 原生通知点击的 `route_token` 会通过一次性 `magicchat/push` 方法传入 Flutter，并在应用恢复时消费。
- Flutter 注册私有 Server grant 时将 `TargetPlatform.iOS` 映射为契约要求的 `ios`（而不是 Dart enum 的 `iOS`），并在设备令牌可用时先完成公共 Gateway installation/grant 生命周期。
- 定向测试：`flutter test test/push_token_provider_test.dart`，14 tests passed；`push_registration_store_test.dart` 通过 1 项安全存储测试。
- 配置路径构建：`JPUSH_APP_KEY=dummy JPUSH_CHANNEL=ci ./gradlew assembleDebug --no-daemon`，Gradle 构建成功。

## 限制

JPush AppKey 是公开构建参数，Master Secret 仍只允许配置在 Push Gateway；真实 APNs/JPush 凭据、厂商渠道参数和通知服务
权限仍需按发布环境配置，因此本证据不代表所有平台真实推送均可达。
