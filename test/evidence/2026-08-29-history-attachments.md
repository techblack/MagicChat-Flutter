# Flutter 历史附件列表阶段测试报告

- 日期：`2026-08-29`
- 分支：`feat/flutter-signal-client`
- 覆盖范围：会话历史附件模型、cursor 分页请求、历史附件对话框的下一页加载

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format lib/data/repository.dart lib/domain/models.dart lib/features/messages/history_attachments_dialog.dart test/history_attachments_test.dart` | 通过 | 本阶段 Dart 文件格式 |
| `flutter test test/history_attachments_test.dart` | 通过，3 tests | 服务端字段解析、HTTP query、分页 UI |
| `git diff --check` | 通过 | 空白错误检查 |

## 已实现契约

- `ConversationAttachment` 对齐 `created_at`、`file_id`、`message_id`、`name`、`seq`、`size_bytes` 字段；`AttachmentPage` 解析可空 `next_cursor`。
- `HttpMagicChatRepository.attachments` 调用 `GET /api/client/conversations/{conversation_id}/attachments`，发送 `cursor` 和 `limit`，并解包标准 `data` envelope。
- 消息输入区文件夹入口打开历史附件对话框；列表按服务端新到旧顺序展示，使用现有临时文件访问地址打开附件，并支持继续加载下一页。

## 未覆盖项

附件下载由服务端临时 URL 和系统外部应用承载，未在无真实对象存储的本地 Widget 测试中发起下载；完整 Flutter 回归和 CI 构建由主分支流水线执行。
