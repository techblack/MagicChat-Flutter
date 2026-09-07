#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct NotificationRoute {
    std::string conversation_id;
    std::string message_id;
  };

  bool ShowNotification(const flutter::EncodableMap& arguments);
  void OpenNotification(UINT notification_id);
  void RemoveNotification(UINT notification_id);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      desktop_window_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      notification_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      push_channel_;
  std::map<UINT, NotificationRoute> notification_routes_;
  UINT next_notification_id_ = 4103;
  bool tray_ready_ = false;
  bool quit_on_close_preference_ = false;
  bool start_hidden_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
