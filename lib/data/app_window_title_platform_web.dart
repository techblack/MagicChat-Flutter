import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'app_window_title_platform_interface.dart';
import 'desktop_window_controller.dart';

const _faviconBlinkInterval = Duration(milliseconds: 500);

AppWindowTitlePlatform createAppWindowTitlePlatform({
  DesktopWindowController? desktopWindowController,
}) =>
    _WebAppWindowTitlePlatform();

class _WebAppWindowTitlePlatform implements AppWindowTitlePlatform {
  _WebAppWindowTitlePlatform() {
    final favicon = _faviconLink();
    _defaultFaviconHref = favicon.getAttribute('href') ?? 'favicon.png';
    _defaultFaviconType = favicon.getAttribute('type') ?? 'image/png';
    _visibilityListener = ((web.Event _) => _syncBlink()).toJS;
    web.document.addEventListener('visibilitychange', _visibilityListener);
  }

  late final String _defaultFaviconHref;
  late final String _defaultFaviconType;
  late final JSFunction _visibilityListener;
  Timer? _blinkTimer;
  bool _alert = false;
  bool _showingDefaultFavicon = true;

  @override
  Future<void> update({required String title, required bool alert}) async {
    web.document.title = title;
    _alert = alert;
    _syncBlink();
  }

  void _syncBlink() {
    if (!_alert || !web.document.hidden) {
      _blinkTimer?.cancel();
      _blinkTimer = null;
      _showDefaultFavicon();
      return;
    }
    if (_blinkTimer != null) return;
    _showDefaultFavicon();
    _blinkTimer = Timer.periodic(_faviconBlinkInterval, (_) {
      _showingDefaultFavicon = !_showingDefaultFavicon;
      if (_showingDefaultFavicon) {
        _setFavicon(_defaultFaviconHref, _defaultFaviconType);
      } else {
        _setFavicon('transparent-favicon.svg', 'image/svg+xml');
      }
    });
  }

  void _showDefaultFavicon() {
    _showingDefaultFavicon = true;
    _setFavicon(_defaultFaviconHref, _defaultFaviconType);
  }

  void _setFavicon(String href, String type) {
    final favicon = _faviconLink();
    favicon
      ..setAttribute('href', href)
      ..setAttribute('type', type);
  }

  web.HTMLLinkElement _faviconLink() {
    final current =
        web.document.querySelector('link[rel~="icon"]') as web.HTMLLinkElement?;
    if (current != null) return current;
    final favicon = web.document.createElement('link') as web.HTMLLinkElement;
    favicon
      ..rel = 'icon'
      ..href = 'favicon.png'
      ..type = 'image/png';
    web.document.head?.append(favicon);
    return favicon;
  }

  @override
  Future<void> dispose() async {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _showDefaultFavicon();
    web.document.removeEventListener('visibilitychange', _visibilityListener);
  }
}
