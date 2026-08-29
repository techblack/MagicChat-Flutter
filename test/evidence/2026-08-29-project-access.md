# Flutter 项目检索与访问控制阶段测试报告

- 日期：2026-08-29
- 分支：`feat/flutter-signal-client`
- 覆盖范围：项目关键词过滤、项目分页响应、成员列表、群组授权绑定/解除、目标占位入口

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format lib/domain/models.dart lib/data/repository.dart lib/features/projects/projects_page.dart test/project_repository_test.dart test/projects_page_test.dart` | 通过 | 本阶段 Dart 文件格式化 |
| `flutter analyze --no-pub` | 构建检查通过；57 条仓库既有 info，无 error/warning | Flutter 工程静态检查 |
| `flutter test --no-pub test/project_repository_test.dart test/projects_page_test.dart` | 通过，16 tests | 项目/群组分页与写接口、成员解析、搜索、目标/成员入口、授权对话框及既有项目回归 |
| `flutter test --no-pub test/widget_test.dart` | 通过，2 tests | 一级导航与会话草稿回归 |
| `flutter test --no-pub` | 通过，36 tests | Flutter 工程全量单元与 Widget 回归 |
| `flutter build web --target=test_driver/project_workspace_harness.dart --release --no-wasm-dry-run` | 通过 | Flutter Web 发布构建入口 |
| `go test ./internal/api/http/client -run TestProjectAndTaskAPIsMapAuthenticatedAccountToApplicationCommands -count=1` | 通过 | Server 项目列表 keyword 透传回归 |
| `git diff --check` | 通过 | 空白错误检查 |

## 已实现契约

- 项目列表仓储按服务端 `next_cursor` 连续读取，个人项目只在第一页保留；页面按名称和描述进行关键词过滤。
- Server 的项目列表 HTTP 层现已透传 `keyword` 到已有项目 Service，分页请求可携带名称/描述搜索条件。
- 群组使用 `/api/client/projects/:project_id/groups` 的 GET/PUT/DELETE 路由，保留成员数、状态和关联时间。
- 成员使用 `/api/client/projects/:project_id/members` 的游标分页；服务端返回隐藏资料字段时通过已有用户解析接口补齐资料，并以用户 ID 作为稳定回退，展示角色和来源群组数量。
- 项目详情增加“成员”视图；普通项目长按菜单提供“授权群组”，个人项目不显示该入口。
- 服务端和 Web/桌面当前没有 Goals API 或持久化模型，Flutter “目标”入口明确显示“待完善”，不发送虚构请求。

## 流程证据

本阶段复用已有 Flutter Web/Chromium 流程入口与测试数据；既有截图覆盖项目概览、任务看板、文档目录、Markdown 预览、任务动态和负责人选择。本阶段新增的搜索、成员和授权交互由定向 Widget 测试覆盖，未生成包含真实账号数据的新截图。

## 结论与未覆盖项

本阶段通过：Flutter 项目列表与项目访问关系已对齐当前服务端真实契约，项目成员和群组授权可操作，Goals 与其他客户端保持占位一致。

仍未完成的长期能力包括文档正文 Hocuspocus/Yjs 协作、Goals 后端设计与实现，以及跨平台真机矩阵；这些需要先有服务端协议或目标平台环境，不能由本地 UI 伪造完成。
