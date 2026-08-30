# Flutter 消息缓存隔离与历史分页验证

## 范围

- 本地消息缓存键包含 Server 地址、用户 ID 和会话 ID，同一会话不会在账号或 Server
  切换后串数据。
- 缓存 JSON 损坏时自动删除并回源，不阻塞消息首屏；设置页“清理缓存”、退出登录和切换
  Server 会删除新旧消息缓存键，但保留文档草稿等其他偏好数据。
- HTTP 消息仓储保留服务端 `page.has_more_before`、序号范围和 limit；历史滚动使用该
  元数据，并在空页或重复边界时停止请求。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/message_cache_store.dart lib/domain/models.dart lib/data/repository.dart lib/data/storage_service_io.dart lib/data/storage_service_stub.dart lib/main.dart test/message_cache_store_test.dart test/project_repository_test.dart` | 通过 | 缓存、仓储、消息页和平台存储格式 |
| `flutter test --no-pub test/message_cache_store_test.dart test/project_repository_test.dart test/message_snapshot_repository_test.dart test/message_choice_test.dart test/message_reaction_test.dart test/settings_page_test.dart test/widget_test.dart` | 通过（28 项） | 账号/Server 隔离、损坏恢复、清理、分页元数据及消息回归 |
| `flutter build web --release --no-wasm-dry-run` | 通过 | Flutter Web 发布编译 |
| `git diff --check` | 通过 | 空白检查 |

## 流程截图

消息快照与选择/回应流程截图见 `test/evidence/message_snapshot.png`、
`test/evidence/message_choice.png` 和 `test/evidence/message_reaction_users.png`；缓存层
本身无新增可视控件，使用仓储与存储单测验证数据边界。

## 未覆盖项

真实设备文件系统崩溃恢复、跨进程并发写入以及服务端在线增量同步压力仍需在 Android/iOS/
Windows/macOS/Linux 真机或 CI Runner 上继续验收。
