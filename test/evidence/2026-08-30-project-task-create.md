# Flutter 新建任务完整表单验证

## 范围

- 新建任务支持标题、Markdown 描述、优先级、负责人、开始/截止日期、逗号分隔标签和提醒配置。
- 负责人从当前项目成员接口加载；创建请求沿用 `/api/client/projects/{project_id}/tasks`，不在客户端伪造任务数据。
- Demo 与 HTTP 仓储保持同一可选字段契约，创建失败显示可重试前的明确错误提示。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/repository.dart lib/features/projects/projects_page.dart test/project_repository_test.dart test/projects_page_test.dart` | 通过 | 表单、仓储与测试格式 |
| `flutter test --no-pub test/project_repository_test.dart test/projects_page_test.dart` | 通过（25 项） | HTTP 字段映射、表单交互、成员选择和错误路径 |
| `flutter build web --release --no-wasm-dry-run` | 通过 | Flutter Web 发布编译 |
| `git diff --check` | 通过 | 空白检查 |

## 流程截图

项目工作区与任务摘要截图见 [`project_task_pagination.png`](project_task_pagination.png)
和 [`project_task_list_summary.png`](project_task_list_summary.png)；本阶段新增字段由
Widget 交互测试逐项提交并断言，未使用真实账号或生产凭据。

## 未覆盖项

真实账号权限、提醒调度器实际触发、跨平台系统日期选择器和 Android/iOS/Windows/macOS/Linux
真机输入矩阵仍需在对应设备与服务端数据上验收。
