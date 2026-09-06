import 'dart:async';

import 'package:desktop_tray/desktop_tray.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import 'chat_preferences.dart';
import 'desktop_tray_model.dart';
import 'desktop_window_controller.dart';

class DesktopSystemTray with DesktopTrayListener {
  DesktopSystemTray({
    DesktopWindowController? windowController,
    TargetPlatform? platform,
  })  : _windowController =
            windowController ?? const PlatformDesktopWindowController(),
        _platform = platform;

  static const _conversationKeyPrefix = 'conversation:';
  static const _iconAsset = 'assets/tray_icon.png';

  final DesktopWindowController _windowController;
  final TargetPlatform? _platform;
  void Function(String conversationId)? _onOpenConversation;
  List<DesktopTrayMessageItem> _messages = const [];
  int _unreadCount = 0;
  bool _initialized = false;
  Future<void> _refreshQueue = Future.value();

  TargetPlatform get _targetPlatform => _platform ?? defaultTargetPlatform;

  bool get _isDesktop =>
      _targetPlatform == TargetPlatform.windows ||
      _targetPlatform == TargetPlatform.macOS ||
      _targetPlatform == TargetPlatform.linux;

  Future<bool> initialize({
    required void Function(String conversationId) onOpenConversation,
  }) async {
    if (!_isDesktop) return false;
    if (_targetPlatform == TargetPlatform.linux &&
        !await desktopTray.checkAvailable()) {
      return false;
    }
    _onOpenConversation = onOpenConversation;
    desktopTray.addListener(this);
    try {
      await desktopTray.setIcon(_iconAsset);
      _initialized = true;
      await _refresh();
      await _windowController.setTrayReady(true);
      return true;
    } catch (_) {
      _initialized = false;
      desktopTray.removeListener(this);
      await desktopTray.destroy();
      return false;
    }
  }

  Future<void> update({
    required int unreadCount,
    required Iterable<ChatConversation> conversations,
    required MessageNotificationPrivacy privacy,
    Iterable<Contact> contacts = const [],
  }) async {
    if (!_initialized) return;
    _unreadCount = unreadCount.clamp(0, 9999).toInt();
    _messages = desktopTrayMessages(conversations, privacy, contacts: contacts);
    _refreshQueue = _refreshQueue.then(
      (_) => _refresh(),
      onError: (_) => _refresh(),
    );
    try {
      await _refreshQueue;
    } catch (_) {
      // 托盘是可选的系统集成，菜单刷新失败不应影响主界面和实时连接。
    }
  }

  Future<void> _refresh() async {
    await desktopTray.setToolTip(desktopTrayToolTip(_unreadCount));
    final items = <TrayMenuItem>[];
    if (_targetPlatform != TargetPlatform.macOS) {
      items.add(TrayMenuItem(label: '未读消息', disabled: true));
      if (_messages.isEmpty) {
        items.add(TrayMenuItem(label: '暂无未读消息', disabled: true));
      } else {
        items.addAll(_messages.map((message) => TrayMenuItem(
              key: '$_conversationKeyPrefix${message.conversationId}',
              label: message.label,
            )));
      }
      items.add(TrayMenuItem.separator());
    }
    items
      ..add(TrayMenuItem(key: 'show', label: '打开 MagicChat'))
      ..add(TrayMenuItem(key: 'quit', label: '退出 MagicChat'));
    await desktopTray.setContextMenu(TrayMenu(items: items));
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(desktopTray.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(TrayMenuItem item) {
    unawaited(handleMenuAction(item.key));
  }

  @visibleForTesting
  Future<void> handleMenuAction(String? key) async {
    if (key == 'show') {
      await _windowController.show();
      return;
    }
    if (key == 'quit') {
      await _windowController.quit();
      return;
    }
    if (key?.startsWith(_conversationKeyPrefix) == true) {
      final conversationId = key!.substring(_conversationKeyPrefix.length);
      if (conversationId.isEmpty) return;
      _onOpenConversation?.call(conversationId);
      await _windowController.show();
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    desktopTray.removeListener(this);
    await _windowController.setTrayReady(false);
    await desktopTray.destroy();
  }
}
