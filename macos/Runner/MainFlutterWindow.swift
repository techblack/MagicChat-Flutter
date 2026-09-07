import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let startHidden = CommandLine.arguments.contains("--hidden")
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    (NSApplication.shared.delegate as? AppDelegate)?.registerNotificationChannels(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    let badgeChannel = FlutterMethodChannel(
      name: "magicchat/app_badge",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    badgeChannel.setMethodCallHandler { call, result in
      guard call.method == "setCount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let count = max(0, arguments?["count"] as? Int ?? 0)
      NSApplication.shared.dockTile.badgeLabel = count == 0 ? nil : String(count)
      result(true)
    }

    let desktopWindowChannel = FlutterMethodChannel(
      name: "magicchat/desktop_window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    desktopWindowChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        self?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        result(true)
      case "setTitle":
        guard let title = call.arguments as? String else {
          result(FlutterError(
            code: "invalid_args",
            message: "setTitle expects a string",
            details: nil
          ))
          return
        }
        self?.title = title
        result(true)
      case "setTrayReady":
        result(true)
      case "setCloseBehavior":
        let behavior = call.arguments as? String
        (NSApplication.shared.delegate as? AppDelegate)?.quitOnClose = behavior == "quit"
        result(true)
      case "quit":
        result(true)
        DispatchQueue.main.async {
          NSApplication.shared.terminate(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    if startHidden {
      orderOut(nil)
      DispatchQueue.main.async { [weak self] in
        self?.orderOut(nil)
      }
    }
  }
}
