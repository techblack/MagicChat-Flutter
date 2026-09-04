import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

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

    super.awakeFromNib()
  }
}
