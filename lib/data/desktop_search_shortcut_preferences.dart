import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_search_shortcut_types.dart';

class DesktopSearchShortcutPreferences {
  const DesktopSearchShortcutPreferences();

  static const shortcutKey = 'magicchat.desktop.search-shortcut.v1';

  Future<DesktopSearchShortcut> read(TargetPlatform platform) async {
    final encoded =
        (await SharedPreferences.getInstance()).getString(shortcutKey);
    if (encoded == null) return DesktopSearchShortcut.defaultFor(platform);
    try {
      final value = jsonDecode(encoded);
      return value is Map<String, dynamic>
          ? DesktopSearchShortcut.fromJson(value, platform)
          : DesktopSearchShortcut.defaultFor(platform);
    } catch (_) {
      return DesktopSearchShortcut.defaultFor(platform);
    }
  }

  Future<void> write(DesktopSearchShortcut shortcut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(shortcutKey, jsonEncode(shortcut.toJson()));
  }
}
