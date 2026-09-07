import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  var quitOnClose = false
  private var pushChannel: FlutterMethodChannel?
  private var pendingConversationID = ""
  private var pendingMessageID = ""

  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    super.applicationDidFinishLaunching(notification)
  }

  func registerNotificationChannels(binaryMessenger: FlutterBinaryMessenger) {
    let push = FlutterMethodChannel(
      name: "magicchat/push",
      binaryMessenger: binaryMessenger
    )
    pushChannel = push
    push.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      guard call.method == "getPendingRoute" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self.takePendingRoute())
    }

    let notifications = FlutterMethodChannel(
      name: "magicchat/notifications",
      binaryMessenger: binaryMessenger
    )
    notifications.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "getPermissionStatus":
        center.getNotificationSettings { settings in
          let status: String
          switch settings.authorizationStatus {
          case .authorized, .provisional:
            status = "granted"
          case .denied:
            status = "denied"
          case .notDetermined:
            status = "notDetermined"
          @unknown default:
            status = "unknown"
          }
          DispatchQueue.main.async { result(status) }
        }
      case "requestPermission":
        center.requestAuthorization(options: [.alert]) { granted, error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(
                code: "permission",
                message: error.localizedDescription,
                details: nil
              ))
            } else {
              result(granted)
            }
          }
        }
      case "showMessage":
        let arguments = call.arguments as? [String: Any]
        let conversationID = arguments?["conversation_id"] as? String ?? ""
        guard !conversationID.isEmpty else {
          result(FlutterError(
            code: "invalid_args",
            message: "showMessage expects a conversation_id",
            details: nil
          ))
          return
        }
        let messageID = arguments?["message_id"] as? String ?? ""
        let content = UNMutableNotificationContent()
        content.title = arguments?["title"] as? String ?? "新消息"
        content.body = arguments?["body"] as? String ?? ""
        content.userInfo = [
          "conversation_id": conversationID,
          "message_id": messageID,
        ]
        let identifier = "magicchat-\(conversationID)-\(messageID)"
        center.add(UNNotificationRequest(
          identifier: identifier,
          content: content,
          trigger: nil
        )) { error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(
                code: "notification",
                message: error.localizedDescription,
                details: nil
              ))
            } else {
              result(true)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let route = response.notification.request.content.userInfo
    pendingConversationID = route["conversation_id"] as? String ?? ""
    pendingMessageID = route["message_id"] as? String ?? ""
    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let pushChannel, let route = pendingRoute() {
      pushChannel.invokeMethod("routeOpened", arguments: route) { [weak self] response in
        if response == nil {
          self?.clearPendingRoute(matching: route)
        }
      }
    }
    completionHandler()
  }

  private func takePendingRoute() -> [String: String]? {
    let route = pendingRoute()
    pendingConversationID = ""
    pendingMessageID = ""
    return route
  }

  private func pendingRoute() -> [String: String]? {
    guard !pendingConversationID.isEmpty || !pendingMessageID.isEmpty else {
      return nil
    }
    return [
      "conversation_id": pendingConversationID,
      "message_id": pendingMessageID,
    ]
  }

  private func clearPendingRoute(matching route: [String: String]) {
    guard route["conversation_id"] == pendingConversationID,
          route["message_id"] == pendingMessageID else {
      return
    }
    pendingConversationID = ""
    pendingMessageID = ""
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return quitOnClose
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      sender.windows.first?.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
