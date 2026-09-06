import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_screenshot_types.dart';

class DesktopScreenshotPreferences {
  const DesktopScreenshotPreferences();

  static const shortcutKey = 'magicchat.desktop.screenshot-shortcut.v1';

  Future<DesktopScreenshotShortcut> read(TargetPlatform platform) async {
    final encoded =
        (await SharedPreferences.getInstance()).getString(shortcutKey);
    if (encoded == null) return DesktopScreenshotShortcut.defaultFor(platform);
    try {
      final value = jsonDecode(encoded);
      return value is Map<String, dynamic>
          ? DesktopScreenshotShortcut.fromJson(value, platform)
          : DesktopScreenshotShortcut.defaultFor(platform);
    } catch (_) {
      return DesktopScreenshotShortcut.defaultFor(platform);
    }
  }

  Future<void> write(DesktopScreenshotShortcut shortcut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(shortcutKey, jsonEncode(shortcut.toJson()));
  }
}
