import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let apnsTokenKey = "magicchat.apns.deviceToken"
  private let pendingRouteTokenKey = "magicchat.push.pendingRouteToken"
  private let pendingConversationIDKey = "magicchat.push.pendingConversationID"
  private let pendingMessageIDKey = "magicchat.push.pendingMessageID"
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let push = FlutterMethodChannel(
      name: "magicchat/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pushChannel = push
    push.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "getDeviceToken":
        guard let token = UserDefaults.standard.string(forKey: self.apnsTokenKey),
              !token.isEmpty else {
          UIApplication.shared.registerForRemoteNotifications()
          result(nil)
          return
        }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        result([
          "provider": "apns",
          "platform": "ios",
          "environment": environment,
          "token": token,
        ])
      case "getPendingRouteToken":
        let token = UserDefaults.standard.string(forKey: self.pendingRouteTokenKey)
        UserDefaults.standard.removeObject(forKey: self.pendingRouteTokenKey)
        result(token)
      case "getPendingRoute":
        let defaults = UserDefaults.standard
        let route: [String: String] = [
          "route_token": defaults.string(forKey: self.pendingRouteTokenKey) ?? "",
          "conversation_id": defaults.string(forKey: self.pendingConversationIDKey) ?? "",
          "message_id": defaults.string(forKey: self.pendingMessageIDKey) ?? "",
        ]
        defaults.removeObject(forKey: self.pendingRouteTokenKey)
        defaults.removeObject(forKey: self.pendingConversationIDKey)
        defaults.removeObject(forKey: self.pendingMessageIDKey)
        result(route)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let notifications = FlutterMethodChannel(
      name: "magicchat/notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notifications.setMethodCallHandler { call, result in
      switch call.method {
      case "getPermissionStatus":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let status: String
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral:
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
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        ) { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "permission", message: error.localizedDescription, details: nil))
            } else {
              if granted {
                UIApplication.shared.registerForRemoteNotifications()
              }
              result(granted)
            }
          }
        }
      case "showMessage":
        let arguments = call.arguments as? [String: Any]
        let title = arguments?["title"] as? String ?? "新消息"
        let body = arguments?["body"] as? String ?? ""
        let conversationID = arguments?["conversation_id"] as? String ?? "magicchat"
        let messageID = arguments?["message_id"] as? String ?? ""
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.userInfo = [
          "conversation_id": conversationID,
          "message_id": messageID,
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
          identifier: "magicchat-\(conversationID.hashValue)",
          content: content,
          trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "notification", message: error.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let appBadge = FlutterMethodChannel(
      name: "magicchat/app_badge",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appBadge.setMethodCallHandler { call, result in
      guard call.method == "setCount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let count = max(0, arguments?["count"] as? Int ?? 0)
      UIApplication.shared.applicationIconBadgeNumber = count
      result(true)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: apnsTokenKey)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    UserDefaults.standard.removeObject(forKey: apnsTokenKey)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let token = routeToken(from: response.notification.request.content.userInfo) {
      UserDefaults.standard.set(token, forKey: pendingRouteTokenKey)
    }
    if let conversationID = response.notification.request.content.userInfo["conversation_id"] as? String,
       !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      UserDefaults.standard.set(conversationID, forKey: pendingConversationIDKey)
    }
    if let messageID = response.notification.request.content.userInfo["message_id"] as? String,
       !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      UserDefaults.standard.set(messageID, forKey: pendingMessageIDKey)
    }
    pushChannel?.invokeMethod("routeOpened", arguments: [
      "route_token": UserDefaults.standard.string(forKey: pendingRouteTokenKey) ?? "",
      "conversation_id": UserDefaults.standard.string(forKey: pendingConversationIDKey) ?? "",
      "message_id": UserDefaults.standard.string(forKey: pendingMessageIDKey) ?? "",
    ])
    completionHandler()
  }

  private func routeToken(from userInfo: [AnyHashable: Any]) -> String? {
    if let token = userInfo["route_token"] as? String {
      let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    if let aps = userInfo["aps"] as? [String: Any],
       let token = aps["route_token"] as? String {
      let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    return nil
  }
}
