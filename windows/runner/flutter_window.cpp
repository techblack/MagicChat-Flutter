#include "flutter_window.h"

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kQuitFromTrayMessage = WM_APP + 1;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  desktop_window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "magicchat/desktop_window",
          &flutter::StandardMethodCodec::GetInstance());
  desktop_window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "show") {
          const auto window = GetHandle();
          if (window != nullptr) {
            ShowWindow(window, SW_RESTORE);
            SetForegroundWindow(window);
          }
          result->Success();
        } else if (method == "setTrayReady") {
          const auto* ready = std::get_if<bool>(call.arguments());
          tray_ready_ = ready != nullptr && *ready;
          result->Success();
        } else if (method == "setCloseBehavior") {
          const auto* behavior = std::get_if<std::string>(call.arguments());
          quit_on_close_preference_ =
              behavior != nullptr && *behavior == "quit";
          result->Success();
        } else if (method == "quit") {
          result->Success();
          PostMessage(GetHandle(), kQuitFromTrayMessage, 0, 0);
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kQuitFromTrayMessage:
      DestroyWindow(hwnd);
      return 0;
    case WM_CLOSE:
      if (quit_on_close_preference_) {
        DestroyWindow(hwnd);
        return 0;
      }
      // 托盘可用时隐藏窗口；托盘不可用时保留任务栏入口，避免窗口无法恢复。
      ShowWindow(hwnd, tray_ready_ ? SW_HIDE : SW_MINIMIZE);
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
