# 本地 Server Docker 测试环境

## 启动范围

Flutter/API 联调使用仓库根目录的 `compose.yml`。默认只启动必要的
`postgres`、`server`、`document-server` 和 `caddy` 服务；Assistant 依赖真实
LLM/MCP 配置，本阶段不作为 Flutter 回归前置条件。

```bash
docker build --progress=plain \
  -f server/Dockerfile \
  -t ghcr.1ms.run/chaitin/magicchat/server:local .
IMAGE_TAG=local docker compose up -d server
```

## 验证结果（2026-08-30）

| 检查 | 结果 |
| --- | --- |
| Server Dockerfile 构建 | 通过，镜像 `server:local`，约 94 MB |
| `docker compose up -d server` | 通过，PostgreSQL 健康依赖满足 |
| Server 容器 | `running` / `healthy`，监听容器端口 20080 |
| Document Server 容器 | `running` / `healthy`，监听容器端口 20100 |
| PostgreSQL 容器 | `running` / `healthy` |
| Caddy 容器 | `running` / `healthy`，对外 80/443/1443 |
| Server 容器 `/healthz` | HTTP 200 |
| `curl -k https://localhost/gateway-healthz` | HTTP 200 |
| `bash scripts/verify-deploy-config.sh` | `deploy config check passed` |

## API 与后端定向测试

| 检查 | 结果 |
| --- | --- |
| Admin 登录、Dashboard、Settings API | 通过（错误密码按预期返回 401） |
| Client 登录、`/api/client/me` | 通过；未登录会话接口按预期返回 401 |
| `go test ./internal/store ./internal/api/http/admin ./internal/api/http/client` | 通过 |

PostgreSQL 持久卷当前 goose 版本为 39，而仓库迁移文件最新为 00036；启动日志为
`no migrations to run`。这是已有持久卷的历史迁移记录高于当前源码编号，不代表本次
启动漏跑迁移；关键业务表和健康检查均可用。

## 复现说明

- `IMAGE_TAG=local` 仅替换 Compose 中的镜像标签，数据库卷和 Caddy 数据未清理。
- Server、Document Server 端口默认只在 Compose 网络内开放，客户端联调通过 Caddy
  入口访问；`/healthz` 是 SPA 的前端回退页，网关健康检查使用 `/gateway-healthz`。
- Assistant 之前因日志挂载目录权限及占位 MCP 地址退出；未修改其配置，也未输出任何
  凭据。
