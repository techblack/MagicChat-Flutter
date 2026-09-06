import 'dart:async';

enum FriendDataRefreshIntent { requests, directory }

typedef FriendDataRefreshCallback = Future<void> Function(
    FriendDataRefreshIntent intent);

class ContactDirectoryRefreshScheduler {
  ContactDirectoryRefreshScheduler(this._refresh);

  final FriendDataRefreshCallback _refresh;
  FriendDataRefreshIntent? _queuedIntent;
  FriendDataRefreshIntent? _trailingIntent;
  bool _scheduled = false;
  bool _running = false;
  bool _disposed = false;

  void request(FriendDataRefreshIntent intent) {
    if (_disposed) return;
    if (_running) {
      _trailingIntent = mergeFriendDataRefreshIntent(_trailingIntent, intent);
      return;
    }
    _queuedIntent = mergeFriendDataRefreshIntent(_queuedIntent, intent);
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      final initial = _queuedIntent;
      _queuedIntent = null;
      if (_disposed || _running || initial == null) return;
      _running = true;
      unawaited(_drain(initial));
    });
  }

  Future<void> _drain(FriendDataRefreshIntent initial) async {
    var intent = initial;
    while (!_disposed) {
      try {
        await _refresh(intent);
      } catch (_) {
        // 单次同步失败不中断后续 realtime 刷新。
      }
      final trailing = _trailingIntent;
      _trailingIntent = null;
      if (trailing == null) break;
      intent = trailing;
    }
    _running = false;
  }

  void dispose() {
    _disposed = true;
    _queuedIntent = null;
    _trailingIntent = null;
  }
}

FriendDataRefreshIntent mergeFriendDataRefreshIntent(
        FriendDataRefreshIntent? current, FriendDataRefreshIntent next) =>
    current == FriendDataRefreshIntent.directory ||
            next == FriendDataRefreshIntent.directory
        ? FriendDataRefreshIntent.directory
        : FriendDataRefreshIntent.requests;
