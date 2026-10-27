import Flutter
import Foundation
import WebKit

/// Swift native manager for OOG/W00g gadget bypass and static asset caching on iOS and macOS.
@objc public class IOSGadgetBypassManager: NSObject {
  @objc public private(set) var isEnabled: Bool = false
  @objc public private(set) var endpoint: String =
    "https://raw.githubusercontent.com/poooi/poi/master/assets/js/gadget.js"

  @objc public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let args = call.arguments as? [String: Any] else {
        result(["success": false, "error": "invalid_arguments"])
        return
      }
      let requestedEnabled = args["enabled"] as? Bool ?? false
      let requestedEndpoint = args["endpoint"] as? String ?? endpoint

      self.isEnabled = requestedEnabled
      self.endpoint = requestedEndpoint

      result([
        "success": true,
        "endpoint": endpoint,
      ])
    case "status":
      result([
        "enabled": isEnabled,
        "endpoint": endpoint,
        // 原生没有实现请求拦截，如实报不支持，Dart 端会禁用开关并显示提示。
        "supported": false,
        "cacheBytes": 0,
      ])
    case "clearCache":
      result(["success": true])
    case "diagnose":
      let unsupported: [String: Any] = ["reachable": false, "elapsedMs": 0, "error": "unsupported"]
      result(["w00g": unsupported, "endpoint": unsupported])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
