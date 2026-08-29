# Flutter 语音消息播放补齐

## 差异结论

Flutter 原先在语音消息上直接调用系统 `launchUrl`，没有 Web/Mobile 已有的应用内播放、暂停、单实例播放和转录展开能力。本阶段改为 `VoiceMessagePlayer`：点击后才请求并缓存临时文件 URL，展示服务端 `duration_ms`，支持播放/暂停，切换另一条语音时自动暂停前一条，转录可展开/收起，播放失败可重新获取 URL。录音发送补齐真实录音时长（服务端要求正整数）；文件选择器中的普通音频按文件发送，避免伪装成缺少时长的语音消息。

## 修改边界

- `lib/features/messages/voice_message_player.dart`：播放器组件、时长解析和单实例播放状态。
- `lib/data/voice_recorder.dart`：记录本次录音的毫秒时长。
- `lib/main.dart`：语音消息使用组件；图片和普通文件仍保持原有预览/下载逻辑。
- `pubspec.yaml` / `pubspec.lock` 与桌面插件注册：加入 `audioplayers` 跨平台实现。

## 验证

| 命令 | 结果 | 覆盖 |
| --- | --- | --- |
| `flutter pub get` | 通过 | 解析 `audioplayers` 及 Android/iOS/Web/Linux/Windows 桥接包 |
| `dart format lib/features/messages/voice_message_player.dart test/voice_message_player_test.dart` | 通过 | Dart 格式 |
| `flutter test test/voice_message_player_test.dart` | 通过，5 项 | 时长格式化、服务端时长校验、multipart 时长/转录字段、播放器文案/转录折叠 UI、golden 截图 |
| `flutter analyze --no-pub lib/features/messages/voice_message_player.dart lib/main.dart test/voice_message_player_test.dart` | 通过，无 error | 静态检查；仅 `main.dart` 既有 info lint |
| `flutter build web --no-pub` | 构建产物生成 | Web 编译及插件注册 |

真机播放仍需在对应平台授予音频输出权限并使用有效临时文件 URL 验收；本地 widget 测试不访问真实媒体服务。

![语音播放器](voice_message_player.png)
