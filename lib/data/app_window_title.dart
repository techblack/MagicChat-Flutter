import 'app_window_title_platform.dart';
import 'app_window_title_platform_interface.dart';
import 'desktop_window_controller.dart';

export 'app_window_title_platform_interface.dart';

class AppWindowTitleState {
  const AppWindowTitleState({
    required this.moduleTitle,
    this.conversationTitle,
    this.totalUnread = 0,
    this.notifiableUnread = 0,
    this.appName = 'MagicChat',
  });

  final String moduleTitle;
  final String? conversationTitle;
  final int totalUnread;
  final int notifiableUnread;
  final String appName;

  String get pageTitle {
    final conversation = conversationTitle?.trim();
    final contextTitle = conversation != null && conversation.isNotEmpty
        ? conversation
        : moduleTitle.trim();
    final app = appName.trim().isEmpty ? 'MagicChat' : appName.trim();
    final page = contextTitle.isEmpty ? app : '$contextTitle - $app';
    return totalUnread > 0 ? '($totalUnread) $page' : page;
  }

  bool get hasMessageAlert => notifiableUnread > 0;

  @override
  bool operator ==(Object other) =>
      other is AppWindowTitleState &&
      moduleTitle == other.moduleTitle &&
      conversationTitle == other.conversationTitle &&
      totalUnread == other.totalUnread &&
      notifiableUnread == other.notifiableUnread &&
      appName == other.appName;

  @override
  int get hashCode => Object.hash(
        moduleTitle,
        conversationTitle,
        totalUnread,
        notifiableUnread,
        appName,
      );
}

class AppWindowTitleController {
  AppWindowTitleController({
    AppWindowTitlePlatform? platform,
    DesktopWindowController? desktopWindowController,
  }) : _platform = platform ??
            createAppWindowTitlePlatform(
              desktopWindowController: desktopWindowController,
            );

  final AppWindowTitlePlatform _platform;
  AppWindowTitleState? _lastState;
  bool _disposed = false;

  Future<void> update(AppWindowTitleState state) async {
    if (_disposed || state == _lastState) return;
    _lastState = state;
    await _platform.update(
      title: state.pageTitle,
      alert: state.hasMessageAlert,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final appName = _lastState?.appName.trim();
    await _platform.update(
      title: appName == null || appName.isEmpty ? 'MagicChat' : appName,
      alert: false,
    );
    await _platform.dispose();
  }
}
