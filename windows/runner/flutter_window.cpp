#include "flutter_window.h"

#include <shellapi.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {
constexpr UINT kQuitFromTrayMessage = WM_APP + 1;
constexpr UINT kNotificationCallbackMessage = WM_APP + 2;

const std::string* StringArgument(const flutter::EncodableMap& arguments,
                                  const char* name) {
  const auto value = arguments.find(flutter::EncodableValue(name));
  if (value == arguments.end()) {
    return nullptr;
  }
  return std::get_if<std::string>(&value->second);
}
}  // namespace

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
        } else if (method == "setTitle") {
          const auto* title = std::get_if<std::string>(call.arguments());
          if (title == nullptr) {
            result->Error("invalid_args", "setTitle expects a string");
          } else {
            const auto utf16_title = Utf16FromUtf8(*title);
            if (!title->empty() && utf16_title.empty()) {
              result->Error("invalid_title", "setTitle received invalid UTF-8");
            } else {
              ::SetWindowTextW(GetHandle(), utf16_title.c_str());
              result->Success();
            }
          }
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
  notification_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "magicchat/notifications",
          &flutter::StandardMethodCodec::GetInstance());
  notification_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "getPermissionStatus") {
          result->Success(flutter::EncodableValue("granted"));
        } else if (method == "requestPermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "showMessage") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr || !ShowNotification(*arguments)) {
            result->Error("notification", "Unable to show notification");
          } else {
            result->Success(flutter::EncodableValue(true));
          }
        } else {
          result->NotImplemented();
        }
      });
  push_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "magicchat/push",
          &flutter::StandardMethodCodec::GetInstance());
  push_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "getPendingRoute") {
      result->Success();
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
  for (const auto& route : notification_routes_) {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = GetHandle();
    data.uID = route.first;
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
  notification_routes_.clear();
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
    case kNotificationCallbackMessage: {
      const auto notification_id = static_cast<UINT>(wparam);
      if (lparam == NIN_BALLOONUSERCLICK) {
        OpenNotification(notification_id);
      } else if (lparam == NIN_BALLOONHIDE ||
                 lparam == NIN_BALLOONTIMEOUT) {
        RemoveNotification(notification_id);
      }
      return 0;
    }
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

bool FlutterWindow::ShowNotification(
    const flutter::EncodableMap& arguments) {
  const auto* conversation_id = StringArgument(arguments, "conversation_id");
  const auto* message_id = StringArgument(arguments, "message_id");
  const auto* title = StringArgument(arguments, "title");
  const auto* body = StringArgument(arguments, "body");
  if (conversation_id == nullptr || conversation_id->empty() ||
      title == nullptr || body == nullptr) {
    return false;
  }

  const UINT notification_id = next_notification_id_++;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = notification_id;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kNotificationCallbackMessage;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"MagicChat");
  if (!Shell_NotifyIconW(NIM_ADD, &data)) {
    return false;
  }

  notification_routes_.emplace(
      notification_id,
      NotificationRoute{*conversation_id,
                        message_id == nullptr ? "" : *message_id});
  data.uFlags = NIF_INFO;
  wcsncpy_s(data.szInfoTitle, Utf16FromUtf8(*title).c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, Utf16FromUtf8(*body).c_str(), _TRUNCATE);
  data.dwInfoFlags = NIIF_USER | NIIF_NOSOUND;
  if (!Shell_NotifyIconW(NIM_MODIFY, &data)) {
    RemoveNotification(notification_id);
    return false;
  }
  return true;
}

void FlutterWindow::OpenNotification(UINT notification_id) {
  const auto route = notification_routes_.find(notification_id);
  if (route == notification_routes_.end()) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("conversation_id")] =
      flutter::EncodableValue(route->second.conversation_id);
  arguments[flutter::EncodableValue("message_id")] =
      flutter::EncodableValue(route->second.message_id);
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
  push_channel_->InvokeMethod(
      "routeOpened",
      std::make_unique<flutter::EncodableValue>(arguments));
  RemoveNotification(notification_id);
}

void FlutterWindow::RemoveNotification(UINT notification_id) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = notification_id;
  Shell_NotifyIconW(NIM_DELETE, &data);
  notification_routes_.erase(notification_id);
}
