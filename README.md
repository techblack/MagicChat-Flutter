# MagicChat Flutter

[![CI](https://github.com/techblack/MagicChat-Flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/techblack/MagicChat-Flutter/actions/workflows/ci.yml)
[![Release](https://github.com/techblack/MagicChat-Flutter/actions/workflows/release.yml/badge.svg)](https://github.com/techblack/MagicChat-Flutter/actions/workflows/release.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

MagicChat 的跨平台 Flutter 客户端。一套代码覆盖 Android、iOS、Windows、macOS、Linux 和 Web，支持连接自托管 MagicChat Server。

## 功能

- 消息：私聊、群聊、应用会话、话题、回复、转发、回应、选择消息、附件、移动端相册多选/相机图片预览、说明及 Android 进程恢复、桌面文件拖放与截图、语音、Markdown、图表与系统事件
- 联系人：好友目录、好友申请、在线状态、公开群组和应用管理
- 项目：项目、任务、看板、月历、甘特图、评论、提醒、成员与群组授权
- 文档：Markdown 协作编辑、Yjs 富文档、在线协作者状态和文档目录树
- 客户端：多账户、主题切换、全局界面字号、SQLite WAL 消息缓存、连接与运行诊断、会话高级检索、全局搜索、二维码、推送授权、通知提示音和隐私设置、跨平台版本检查
- Android 更新：应用内下载官方 APK、显示进度并打开系统安装器
- 桌面集成：Windows、macOS、Linux 完整包应用内更新、系统托盘、开机静默自启动、未读会话快捷入口、区域/全屏截图、全局快捷键和关闭后后台运行
- 实时同步：WebSocket 游标续传、断线重连、幂等事件投影，以及实时消息先落本地缓存再展示

## 快速开始

需要 Flutter 3.22 或更高版本。

```bash
git clone https://github.com/techblack/MagicChat-Flutter.git
cd MagicChat-Flutter
flutter pub get
flutter run -d chrome
```

首次启动后，在登录页填写 MagicChat Server 地址和账户信息。Native 客户端使用 Bearer Token；Web 客户端使用 Server 下发的 HttpOnly Cookie，Token 不会写入 URL。

## 开发

```bash
dart format lib test test_driver packages/yjs_dart/lib
flutter analyze
flutter test
flutter build web --release
```

Linux 构建还需要 Clang、CMake、Ninja、GTK3、libsecret 和 GStreamer 开发包：

```bash
sudo apt-get install clang cmake ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev \
  libayatana-appindicator3-dev \
  libkeybinder-3.0-dev gnome-screenshot \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
flutter build linux
```

桌面端打开会话后可从输入区选择区域截图或全屏截图，确认预览后作为图片消息发送。默认全局快捷键为 Windows/Linux 的 `Ctrl+Shift+A`、macOS 的 `Command+Shift+A`，可在设置中重新录制或禁用。Linux KDE 会优先使用 Spectacle，其他桌面环境需要 `gnome-screenshot`；macOS 首次使用时需要授予“屏幕录制”权限。

CI 会执行格式、静态检查、单元测试，并构建 Web Release 与 Linux Debug 产物。

“设置 → 连接与运行诊断”会实时检查当前平台和版本、脱敏后的服务器地址、HTTP
可达性与延迟、WebSocket 重连状态、SQLite WAL、缓存占用以及通知权限。诊断记录只
保存在本机；复制的报告不会包含 Token、Cookie、邮箱、消息正文、完整错误文本或请求
Header。客户端未观察到某个事件，不代表服务端未发送该事件。

应用图标以 `linux/runner/resources/magicchat.svg` 为唯一源文件。修改品牌图标后，
使用 ImageMagick 重新生成并校验 Android、iOS、macOS、Windows 和 Web 资源：

```bash
tool/generate_app_icons.sh
tool/verify_app_icons.sh
```

推送与 `pubspec.yaml` 版本一致的 `v*` 标签后，Release 工作流会构建并发布完整的跨平台产物：Android 通用/分 ABI APK 与 AAB、未签名 iOS IPA、macOS、Windows、Linux、Web 压缩包及 SHA-256 校验文件。Android 发布产物使用 GitHub Actions Secrets 中保存的固定 Release 证书，工作流会对照 [`android/release-signing-certificate.sha256`](android/release-signing-certificate.sha256) 校验所有 APK 与 AAB；iOS 产物仍需要使用自己的 Apple 开发者证书重新签名。

macOS Release 为方便未配置 Apple Developer 证书时测试，关闭了 App Sandbox，并使用未经 Apple 公证的临时签名。只应从本仓库 Release 下载并核对 `SHA256SUMS.txt`；解压并移动到“应用程序”后执行：

```bash
xattr -dr com.apple.quarantine /Applications/MagicChat.app
open /Applications/MagicChat.app
```

Windows、macOS 和 Linux 桌面版可在“设置”中开启“开机自动启动”。该选项默认关闭；开启后会注册当前用户的系统启动项，并在登录系统后使用 `--hidden` 参数静默启动。登录页同样保留系统托盘入口；若系统托盘不可用，应用会自动显示主窗口，避免后台运行后无法打开。

Android 推送默认保持安全降级；发布包需要 JPush 时，在构建环境注入应用密钥（不要提交到仓库）：

```bash
JPUSH_APP_KEY="$YOUR_JPUSH_APP_KEY" \
JPUSH_CHANNEL=official \
flutter build apk --release
```

未设置 `JPUSH_APP_KEY` 时不会打包 JPush SDK，其他 Android 构建和测试不受影响。

更新检查默认读取 release 源：Android/iOS 使用
`https://jiying.chat/releases/version.json`，Windows/macOS/Linux 使用本项目的
GitHub Release 产物。构建测试或私有发布源时可通过 Dart 编译参数替换完整 manifest 地址：

```bash
flutter build apk --release \
  --dart-define=MAGICCHAT_UPDATE_SOURCE=https://download.example.com/version.json
```

仓库内默认值保持为 `release`，自定义源必须使用 HTTPS。

Windows、macOS 和 Linux 发现新版本后会在应用内下载对应完整发布包，并在 Release 提供 `SHA256SUMS.txt` 时强制核对摘要。归档路径和平台目录结构通过校验后，新版本会在当前安装目录同盘暂存；应用退出后由独立更新助手备份旧目录、替换并重启。替换或新版本启动失败时会恢复旧目录；安装目录只读、校验失败或包结构异常时，当前版本保持运行并显示错误，不会报告虚假的安装成功。

## 目录

```text
lib/app/                应用装配、认证状态和顶层导航
lib/data/               HTTP、WebSocket、缓存和平台能力适配
lib/domain/             跨平台领域模型与消息内容解析
lib/features/           消息、联系人、项目、搜索和设置页面
packages/yjs_dart/      MagicChat 富文档需要的 Yjs Dart fork
test/                   接口契约、状态模型和 Widget 测试
test_driver/            关键业务流程的集成测试入口
```

`MagicChatRepository` 是页面与服务端之间的统一契约。HTTP API 使用 `/api/client/`，实时连接使用 MagicChat WebSocket envelope。仓库内的 `yjs_dart` fork 基于 1.1.15，补齐了与 Web/Desktop Tiptap 文档互操作所需的 XML 类型支持，并保留其 BSD-3-Clause 许可证。

服务端源码与部署说明见 [MagicChat](https://github.com/chaitin/MagicChat)。当前迁移覆盖和待完善能力见 [MIGRATION.md](MIGRATION.md)。

## 许可证

本项目使用 [GNU AGPL v3](LICENSE)。`packages/yjs_dart` 使用其目录内声明的 BSD-3-Clause 许可证。
