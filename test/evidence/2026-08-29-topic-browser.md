# Flutter 话题浏览与生命周期阶段测试报告

- 日期：`2026-08-29`
- 分支：`feat/flutter-signal-client`
- 覆盖范围：话题模型与 HTTP 仓储、话题列表筛选/游标分页、详情来源消息、参与与关闭、实时状态投影。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format lib/data/realtime_store.dart lib/data/repository.dart lib/domain/models.dart lib/features/messages/topics_dialog.dart test/realtime_store_test.dart test/topic_repository_test.dart test/topics_dialog_test.dart test/topic_screenshot_test.dart test_driver/topics_harness.dart` | 通过 | 本阶段 Dart 文件格式 |
| `flutter test test/topic_repository_test.dart test/topics_dialog_test.dart test/realtime_store_test.dart` | 通过 | 话题数据、页面交互和实时事件 |
| `flutter test test/topic_repository_test.dart test/message_reply_test.dart test/realtime_store_test.dart test/topic_reply_preview_test.dart test/widget_test.dart` | 通过（19 项） | 来源消息回退、话题回复摘要和归档门控 |
| `flutter test test/topic_screenshot_test.dart` | 通过（2 项） | 话题列表和回复预览截图回归 |
| `flutter test --update-goldens test/topic_screenshot_test.dart` | 通过 | 话题列表与回复预览截图基准生成 |
| `flutter test test/topic_screenshot_test.dart` | 通过 | 截图回归 |
| `flutter build web --release --no-wasm-dry-run` | 通过 | 生产 Web 编译 |
| `git diff --check` | 通过 | 空白错误检查 |

### 话题内上下文回归

本次补充通过 `flutter test test/topic_repository_test.dart test/message_reply_test.dart test/realtime_store_test.dart test/widget_test.dart` 验证了来源消息缺失 `reply_to` 时的父会话回退、消息话题摘要的 HTTP/实时解析，以及归档话题发送与消息操作门控。

## 已实现契约

- `ChatConversation` 解析 `can_send`、话题元数据和服务端 `last_message_summary`；详情来源消息保留撤回、回复和发送者信息。
- `HttpMagicChatRepository` 对齐创建、列表、详情、参与和关闭话题路由，支持 URL 编码、状态筛选和 cursor/limit 分页。
- 消息面板提供话题列表入口；列表支持全部/进行中/已关闭筛选、加载更多、去重、重试和详情打开；详情支持参与、关闭和打开话题。
- `RealtimeStore` 投影 `topic.created`、`topic.participated`、`topic.archived`，关闭后将 `canSend` 置为 false，并保持来源元数据。

## 截图

- `test/evidence/topic_list.png`：话题列表、状态标签和参与标记。
- `test/evidence/topic_reply_preview.png`：父会话消息中的话题回复预览及打开入口。

## 未覆盖项

- 真实账号登录和线上 WebSocket 端到端话题流程仍需在 Docker 数据库初始化测试数据后执行；本阶段使用仓储契约测试和 Flutter widget 测试验证。
- 应用厂商推送仍属于后续迁移阶段。
