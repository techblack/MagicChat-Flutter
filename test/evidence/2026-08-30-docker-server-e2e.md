# 本地 Docker Server 与 E2E 复现记录

## 环境

- Docker Engine 28.0.1，Compose v2.33.1
- Flutter 3.47.2，Dart 3.13.2
- `/mnt` 剩余约 82 GB；Compose 数据目录约 77 MB

## Compose 与迁移

以下检查在不停止或删除现有容器的前提下执行：

```bash
docker compose config --quiet
bash scripts/verify-deploy-config.sh
docker compose ps --all --format 'table {{.Service}}\t{{.State}}\t{{.Health}}\t{{.Ports}}'
```

结果：Compose 配置校验通过，部署配置检查输出 `deploy config check passed`；
`postgres`、`server`、`document-server`、`caddy` 均为 `running`/`healthy`。
Assistant 为 `exited (1)`，原因见下文。

Server 启动日志为 `goose: no migrations to run. current version: 39`。
PostgreSQL 只读核验结果为 `goose_db_version` 最大版本 39、40 条记录且全部
`is_applied=true`；`projects`、`tasks`、`mobile_push_events` 表均存在（公共
Schema 共 172 张表）。当前源码迁移文件最新为 `00036_add_mobile_push_events.sql`，
说明该持久卷曾由包含 37--39 版本的历史镜像初始化；本轮没有对现有卷做降级、回滚
或清理。若需验证从零迁移，应另用隔离卷运行，不要复用该测试数据目录。

为验证源码迁移本身，另在 `magic-chat_default` 网络创建了临时 PostgreSQL 和
Server 容器（独立数据库名、仅使用测试占位密钥），Server 日志为
`goose: successfully migrated database to version: 36`，隔离库查询为
`36|37|37|0`（最大版本、记录数、已应用数、未应用数）。验证后仅删除这两个临时
容器，Compose 原有容器和数据未触碰。

## 健康端点与登录链路

端口映射：客户端入口为 `https://localhost`（443），管理端入口为
`https://localhost:1443`；Server 的 20080 和 Document Server 的 20100 只在
Compose 网络内开放。

| 检查 | 结果 |
| --- | --- |
| `https://localhost/healthz` | HTTP 200 |
| `https://localhost/readyz` | HTTP 200 |
| `https://localhost/gateway-healthz` | HTTP 200，body `ok` |
| `https://localhost/api/client/info` | HTTP 200，未认证、密码登录已启用 |
| 未带 Cookie 的 `/api/client/me` | HTTP 401，`unauthorized` |
| 未带 Cookie 的 `/api/client/projects` | HTTP 401，`unauthorized` |
| 未带 Cookie 的 `/api/client/conversations` | HTTP 401，`unauthorized` |
| 管理端错误密码登录 | HTTP 401，`invalid_credentials` |
| 管理端正确密码登录（本地配置值） | HTTP 200，返回 `admin_session` Cookie |
| 管理端带 Cookie `/api/admin/dashboard` | HTTP 200 |
| 普通用户登录后 `/api/client/me` | HTTP 200（随机 E2E 用户，密码未写入报告） |

管理端登录必须使用 1443 端口；在 443 访问 `/api/admin/*` 会命中客户端前端
回退，不代表管理 API 不可用。

## 截图回归复现

服务无关的既有截图测试可复现：

```bash
cd client-flutter
flutter test --no-pub test/document_collaboration_screenshot_test.dart
flutter test --no-pub test/topic_screenshot_test.dart
```

两条命令均输出 `All tests passed!`（各 2 项），对应截图文件已在
`client-flutter/test/evidence/`。任务筛选/响应式布局定稿后，任务列表摘要与任务分页
golden 已重新生成；`flutter test --no-pub test/project_task_list_summary_test.dart
test/projects_page_test.dart` 全部通过，工作区未留下失败截图产物。

## 未覆盖项

Assistant 镜像以 UID 100/GID 101 运行，而宿主 `data/assistant/log` 为 `root:root`
且不可写，日志报 `permission denied` 后退出；同时默认 MCP/LLM 地址是占位配置。
没有真实厂商凭据时不启动或伪造 Assistant WebSocket/LLM E2E 通过。修复该链路需要
提供真实 MCP/LLM 配置，并将日志目录授权给镜像用户。
