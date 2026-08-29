# Flutter 移动端版本检查阶段验证

## 范围

- `UpdateService` 按 Android/iOS 平台读取发布清单，避免 iOS 错用 Android 安装包地址。
- 对版本号、非负整数 build 和 HTTPS 下载地址进行严格校验；发现新 build 时返回下载信息，否则返回空值。

## 自动化验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `dart format --set-exit-if-changed lib/data/update_service.dart test/update_service_test.dart` | 通过 | 本阶段 Dart 格式 |
| `flutter analyze --no-pub lib/data/update_service.dart test/update_service_test.dart` | 通过；无 error/info | 版本服务与测试静态检查 |
| `flutter test test/update_service_test.dart` | 通过（3 项） | HTTPS 校验、平台选择、build 边界 |
| `git diff --check` | 通过 | 空白错误检查 |

## 流程截图

版本入口显示在设置页流程截图中：![设置页版本检查入口](settings_page.png)

真实 Android/iOS 安装包下载与系统安装动作仍需在对应设备验收；桌面端继续使用原生自动更新器。
