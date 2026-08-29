# Flutter 推送通知点击路由

修复 `PushService.resolveRoute` 对服务端成功响应 envelope 的解析。服务端返回 `{success: true, data: {conversation_id, message_id}}`，Flutter 现在解包 `data` 后选择目标会话；同时兼容滚动升级期间的顶层路由对象。

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/push_service.dart test/push_token_provider_test.dart` | 通过 | Dart 格式 |
| `flutter test --no-pub test/push_token_provider_test.dart` | 通过（5 项） | 推送授权降级、过期令牌、撤销和通知路由成功/错误响应 |

该修复属于协议层，无独立可视化界面；通知设置页截图见 [`2026-08-30-settings-page.md`](2026-08-30-settings-page.md)。
