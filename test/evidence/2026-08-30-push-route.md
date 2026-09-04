# Flutter 推送通知点击路由

修复 `PushService` 与当前服务端推送契约的请求方法和响应 envelope。撤销使用 `POST /api/client/push/grants/{installation_id}/revoke` 并发送 `grant_id`，路由解析使用 `POST /api/client/push/routes/resolve` 并发送 `route_token`；成功响应 `{success: true, data: {conversation_id, message_id}}` 会解包后选择目标会话，同时兼容滚动升级期间的顶层路由对象响应体。

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/push_service.dart test/push_token_provider_test.dart` | 通过 | Dart 格式 |
| `flutter test --no-pub test/push_token_provider_test.dart` | 通过（11 项） | 推送授权降级、过期令牌、设备令牌校验、当前撤销和通知路由请求/响应 |

该修复属于协议层，无独立可视化界面；通知设置页截图见 [`2026-08-30-settings-page.md`](2026-08-30-settings-page.md)。
