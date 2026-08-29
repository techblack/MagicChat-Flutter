# Flutter 会话筛选与撤回消息阶段测试报告

- 日期：`2026-08-29`
- 分支：`feat/flutter-signal-client`
- 覆盖范围：会话列表筛选/搜索/排序，以及历史和实时撤回消息的统一展示契约。

## 已实现契约

- 会话列表支持全部、未读、私聊、群聊、应用筛选；话题按父会话类型参与类型筛选，关键词匹配标题、预览和公告。
- 会话按置顶优先、最新消息序号倒序、会话 ID 稳定排序，实时刷新后仍保持确定顺序。
- 服务端撤回消息省略 `body` 时，HTTP 历史、WebSocket 实时事件和通知摘要统一显示“消息已撤回”，并禁用回应、回复、撤回等正文操作。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib test` | 通过 | 本阶段 Dart 格式 |
| `flutter test test/conversation_list_test.dart test/message_content_test.dart test/message_reply_test.dart test/realtime_store_test.dart` | 通过，24 tests | 筛选、排序、搜索、历史/实时撤回契约和 UI 流程 |
| `flutter analyze --no-pub --no-fatal-infos` | 通过；仅既有 info | 本阶段静态检查 |
| `git diff --check` | 通过 | 空白检查 |

## 流程截图

`test/evidence/conversation_filters.png` 展示未读筛选后的会话列表、搜索栏和筛选 Chip；截图由 Flutter Widget 测试生成。

## 未覆盖项

文档正文 Yjs 编辑绑定、推送厂商 SDK 以及 Android/iOS/Windows/macOS/Linux 真机矩阵仍需对应平台依赖或设备后继续迁移。
