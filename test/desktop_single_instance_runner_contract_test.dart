import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux Runner 复用唯一 GtkApplication 的现有窗口', () async {
    final source = await File('linux/runner/my_application.cc').readAsString();

    expect(source, isNot(contains('G_APPLICATION_NON_UNIQUE')));
    final reuseWindow = source.indexOf('if (self->window != nullptr)');
    final createWindow = source.indexOf('gtk_application_window_new');
    expect(reuseWindow, greaterThanOrEqualTo(0));
    expect(createWindow, greaterThan(reuseWindow));
    expect(source, contains('gtk_window_deiconify(self->window)'));
    expect(source, contains('gtk_window_present(self->window)'));
  });

  test('Windows Runner 在 Flutter 初始化前拒绝第二实例', () async {
    final mainSource = await File('windows/runner/main.cpp').readAsString();
    final helperSource =
        await File('windows/runner/single_instance.cpp').readAsString();
    final cmakeSource =
        await File('windows/runner/CMakeLists.txt').readAsString();

    final instanceGuard = mainSource.indexOf('SingleInstance single_instance');
    final notifyPrimary = mainSource.indexOf('single_instance.NotifyPrimary()');
    expect(instanceGuard, greaterThanOrEqualTo(0));
    expect(notifyPrimary, greaterThan(instanceGuard));
    expect(mainSource.indexOf('CoInitializeEx'), greaterThan(notifyPrimary));
    expect(
      mainSource.indexOf('flutter::DartProject'),
      greaterThan(notifyPrimary),
    );
    expect(mainSource, contains('MsgWaitForMultipleObjects'));
    final createEvent = helperSource.indexOf('CreateEventW');
    final createMutex = helperSource.indexOf('CreateMutexW');
    expect(createEvent, greaterThanOrEqualTo(0));
    expect(createMutex, greaterThan(createEvent));
    expect(helperSource, contains('SetLastError(ERROR_SUCCESS)'));
    expect(helperSource, contains('CreateEventW(nullptr, FALSE, FALSE'));
    expect(helperSource, contains('SetEvent(activation_event_)'));
    expect(helperSource, contains(r'Local\\cloud.baizhi.chat.SingleInstance'));
    expect(helperSource, contains(r'Local\\cloud.baizhi.chat.Activate'));
    expect(cmakeSource, contains('"single_instance.cpp"'));
  });

  test('Windows 首实例收到通知后恢复并前置现有窗口', () async {
    final mainSource = await File('windows/runner/main.cpp').readAsString();
    final windowSource =
        await File('windows/runner/flutter_window.cpp').readAsString();

    expect(mainSource, contains('window.Activate()'));
    expect(windowSource, contains('void FlutterWindow::Activate()'));
    expect(windowSource, contains('ShowWindow(window, SW_RESTORE)'));
    expect(windowSource, contains('SetForegroundWindow(window)'));
  });
}
