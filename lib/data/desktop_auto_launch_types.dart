abstract interface class DesktopAutoLaunchController {
  bool get isSupported;

  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);
}

class DesktopAutoLaunchException implements Exception {
  const DesktopAutoLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isHiddenDesktopLaunch(Iterable<String> arguments) =>
    arguments.contains('--hidden');

bool shouldKeepDesktopLaunchHidden({
  required bool hiddenRequested,
  required bool autoLaunchEnabled,
  required bool trayReady,
}) =>
    hiddenRequested && autoLaunchEnabled && trayReady;
