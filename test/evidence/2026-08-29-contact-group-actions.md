# Flutter 通讯录公开群组与好友关系阶段测试报告

- 日期：`2026-08-29`
- 分支：`feat/flutter-signal-client`
- 覆盖范围：公开群组状态、未加入群组的加入流程、会话恢复仓储、删除好友及联系人实时资料保留。

## 已实现契约

- 通讯录群组保留服务端 `joined`、`member_count` 和 `visibility` 字段；未加入的公开群组点击后先调用 `/api/client/conversations/groups/{id}/join`，成功再打开会话。
- 仓储补齐 `/api/client/conversations/{id}/restore` 和 `/api/client/friends/{user_id}`，统一使用 Bearer 认证和 URL 编码。
- “新朋友”弹窗展示当前好友，删除操作要求确认；在线状态实时更新不会覆盖昵称、邮箱、头像等资料字段。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/realtime_store.dart lib/data/repository.dart lib/domain/models.dart lib/features/contacts test/contact_repository_test.dart test/contacts_page_test.dart test/group_repository_test.dart test/realtime_store_test.dart` | 通过 | 本阶段 Dart 格式 |
| `flutter test --no-pub test/contact_repository_test.dart test/contacts_page_test.dart test/group_repository_test.dart test/realtime_store_test.dart` | 通过，20 tests | API 路由、联系人 UI、公开群组加入、好友删除和实时资料 |
| `flutter test` | 通过，68 tests | Flutter 全量单元与 Widget 回归 |
| `flutter analyze --no-pub` | 通过；仅仓库既有 info，无 error/warning | 静态检查 |
| `flutter build web --release --no-wasm-dry-run` | 通过 | Web 发布构建 |
| `flutter build linux --debug` | 通过 | Linux Debug 构建 |
| `git diff --check` | 通过 | 空白检查 |

## 本地服务冒烟

Docker Compose 中 `postgres`、`server`、`document-server`、`caddy` 均为 healthy；Server `/healthz`、Document Server `/healthz`、客户端入口和公开客户端信息接口返回 200，未鉴权会话接口返回 401。Assistant 未启动：默认 MCP 地址为占位地址，且宿主 `data/assistant/log` 为 `root:root`，与镜像 `100:101` 用户不匹配；未提供外部 MCP/模型凭据前不伪造 AI 链路通过。

## 流程截图

本阶段复用 `test/evidence/contacts_directory.png` 与 `friend_management_search.png` 的真实 Flutter Web/Chromium 流程截图；新增的公开群组加入和删除好友确认由 Widget 测试覆盖，测试数据不包含生产凭据。

## 未覆盖项

推送厂商 SDK、文档正文 Yjs 编辑绑定以及 Android/iOS/Windows/macOS/Linux 真机矩阵仍需对应平台依赖或服务端协议后继续迁移。
