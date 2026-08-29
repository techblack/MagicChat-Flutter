# Flutter 群聊与项目创建契约阶段测试报告

- 日期：`2026-08-29`
- 分支：`feat/flutter-signal-client`
- 覆盖范围：群聊成员角色门控、退出/解散、应用成员移除、项目创建时关联群聊、Hocuspocus v4 协作握手

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/document_realtime.dart lib/data/repository.dart lib/features/projects/projects_page.dart lib/main.dart test/document_realtime_test.dart test/group_repository_test.dart test/project_repository_test.dart test/projects_page_test.dart` | 通过 | 本阶段 Dart 文件格式 |
| `flutter analyze --no-pub --no-fatal-infos` | 通过；无 error/warning，保留 55 条仓库既有 info | Flutter 静态检查 |
| `flutter test --no-pub` | 通过，78 tests | Flutter 全量单元与 Widget 回归 |
| `flutter test --no-pub test/document_realtime_test.dart test/group_repository_test.dart test/project_repository_test.dart test/projects_page_test.dart` | 通过，23 tests | 本阶段协议、权限、项目创建与项目回归 |
| `flutter build web --target=test_driver/project_workspace_harness.dart --release --no-wasm-dry-run` | 通过 | Flutter Web 发布构建入口 |
| `git diff --check` | 通过 | 空白错误检查 |

## 已实现契约

- 群聊菜单根据当前成员角色展示操作：成员可改名称、添加用户和退出；管理员/群主可改公告、头像和移除成员；仅群主可切换公开状态和解散群聊。
- 应用成员移除使用服务端的 typed member 路由；用户成员继续使用兼容的简化路由。退出和解散使用现有 `/leave`、`DELETE` 路由。
- 新建项目对齐 Web 行为，在创建表单中加载当前可见群聊、支持搜索和最多 100 个关联群聊，并一次性发送 `group_ids`。
- `DocumentRealtime` 发送 Hocuspocus v4 路由和认证帧，并在收到 `Auth.Authenticated` 后再发送空状态向量 SyncStep1；真实会话凭据仍由原生 Cookie/Authorization 连接器承载，未写入协议 token。正文 Yjs 更新解析和编辑器绑定仍未伪造。

## 本地服务冒烟

Docker Compose 中 `postgres`、`server`、`document-server`、`caddy` 均为 healthy；Server、Document Server 健康端点和 Caddy 客户端/管理端入口返回 200，未登录客户端/管理端 API 返回 401。Compose 声明的 `assistant` 当前未运行，因此 AI Assistant WebSocket/LLM 链路未验证。

已有流程截图继续覆盖项目概览、任务看板、文档目录、Markdown 预览、任务动态和负责人选择；本阶段新增交互由定向 Widget 测试覆盖，未生成包含真实账号数据的截图。

## 未覆盖项

服务端没有普通用户 `set_role` API，Flutter 不添加虚假的管理员设置入口；正文多人协作仍需兼容 Yjs runtime，目标管理仍等待服务端 Goals 契约，APNs/JPush 厂商 SDK 和跨平台真机矩阵待后续阶段。
