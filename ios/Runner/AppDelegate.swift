import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let apnsTokenKey = "magicchat.apns.deviceToken"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let push = FlutterMethodChannel(
      name: "magicchat/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    push.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getDeviceToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self,
            let token = UserDefaults.standard.string(forKey: self.apnsTokenKey),
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
    }
    let notifications = FlutterMethodChannel(
      name: "magicchat/notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notifications.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        ) { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "permission", message: error.localizedDescription, details: nil))
            } else {
              result(granted)
            }
          }
        }
      case "showMessage":
        let arguments = call.arguments as? [String: Any]
        let title = arguments?["title"] as? String ?? "新消息"
        let body = arguments?["body"] as? String ?? ""
        let conversationID = arguments?["conversation_id"] as? String ?? "magicchat"
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
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
}
