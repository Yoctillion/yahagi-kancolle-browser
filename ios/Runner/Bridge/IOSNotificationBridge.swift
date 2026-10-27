import Flutter
import UIKit
import UserNotifications

/// Handles local notification requests on iOS using UserNotifications.framework.
final class IOSNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
  private static let appliedAlarmsKey = "IOSNotificationBridge.appliedAlarms"

  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard

  override init() {
    super.init()
    center.delegate = self
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "applySnapshot":
      guard let snapshot = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_argument", message: "Snapshot dictionary required", details: nil))
        return
      }
      applySnapshot(snapshot, result: result)

    case "getCapabilities":
      center.getNotificationSettings { settings in
        let granted = settings.authorizationStatus == .authorized ||
                      settings.authorizationStatus == .provisional
        DispatchQueue.main.async {
          result([
            "notificationsGranted": granted,
            "exactAlarmsGranted": true,
            "channelsEnabled": true
          ])
        }
      }

    case "requestNotificationPermission":
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        DispatchQueue.main.async {
          if let error = error {
            NSLog("[IOSNotificationBridge] Request authorization error: \(error)")
          }
          result(granted)
        }
      }

    case "requestExactAlarmPermission":
      // iOS has no separate exact alarm permission; local notifications trigger precisely.
      result(nil)

    case "openSystemNotificationSettings":
      DispatchQueue.main.async {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        result(nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private struct Alarm {
    let key: String
    let title: String
    let body: String
    let triggerEpochMs: Double
  }

  // 快照是 Dart 端的完整期望状态，与 Android 一样按上次已排的闹钟做差异：
  // 不在快照里的撤掉，内容变了的重排。已经响过的闹钟 Dart 不会再发，
  // 若每次都全量重排，刚到点的那条会因为 1 秒兜底延迟再响一遍。
  private func applySnapshot(_ snapshot: [String: Any], result: @escaping FlutterResult) {
    let presentation = snapshot["presentation"] as? [String: Any] ?? [:]
    let enabled = presentation["enabled"] as? Bool ?? false
    let sound = presentation["sound"] as? Bool ?? true
    let memberId = (snapshot["memberId"] as? NSNumber)?.int64Value ?? 0
    let sessionId = snapshot["sessionId"] as? String ?? ""

    let alarms = (snapshot["alarms"] as? [[String: Any]] ?? []).compactMap(Self.alarm(from:))
    var nextSignatures: [String: String] = [:]
    for alarm in alarms {
      // 会话与声音设置也算进签名：换号或切换声音时整批重排，对应 Android 的同名逻辑。
      nextSignatures[alarm.key] =
        "\(memberId)|\(sessionId)|\(sound)|\(Int64(alarm.triggerEpochMs))|\(alarm.title)|\(alarm.body)"
    }

    let previousSignatures =
      defaults.dictionary(forKey: Self.appliedAlarmsKey) as? [String: String] ?? [:]
    // 只撤待发的；已送达的通知留在通知中心，否则闹钟一响、下一份快照就会把它删掉。
    let canceledKeys = previousSignatures.keys.filter { nextSignatures[$0] == nil }
    if !canceledKeys.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: Array(canceledKeys))
    }

    // center.add 的回调在后台线程，计数和失败列表统一在串行队列上改。
    let stateQueue = DispatchQueue(label: "IOSNotificationBridge.applySnapshot")
    var scheduledExact = 0
    var failures: [String] = []
    var failedAlarmKeys = Set<String>()
    let group = DispatchGroup()

    func add(_ request: UNNotificationRequest, failure: String, onFailure: @escaping () -> Void = {}) {
      group.enter()
      center.add(request) { error in
        stateQueue.async {
          if let error = error {
            NSLog("[IOSNotificationBridge] %@ error: %@", failure, error.localizedDescription)
            failures.append(failure)
            onFailure()
          } else {
            scheduledExact += 1
          }
          group.leave()
        }
      }
    }

    let nowEpochMs = Date().timeIntervalSince1970 * 1000
    for alarm in alarms where previousSignatures[alarm.key] != nextSignatures[alarm.key] {
      let delaySeconds = max(1.0, (alarm.triggerEpochMs - nowEpochMs) / 1000.0)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delaySeconds, repeats: false)
      let request = UNNotificationRequest(
        identifier: alarm.key,
        content: Self.content(title: alarm.title, body: alarm.body, sound: sound),
        trigger: trigger)
      add(request, failure: "\(alarm.key):schedule") { failedAlarmKeys.insert(alarm.key) }
    }

    if enabled {
      for item in snapshot["immediateAlerts"] as? [[String: Any]] ?? [] {
        guard let key = item["key"] as? String,
              let title = item["title"] as? String,
              let body = item["body"] as? String else {
          continue
        }
        let request = UNNotificationRequest(
          identifier: key,
          content: Self.content(title: title, body: body, sound: sound),
          trigger: nil)
        add(request, failure: "\(key):notify")
      }
    }

    group.notify(queue: stateQueue) {
      // 排失败的不记账，下一份快照会再试一次。
      var applied = nextSignatures
      for key in failedAlarmKeys { applied.removeValue(forKey: key) }
      self.defaults.set(applied, forKey: Self.appliedAlarmsKey)
      let payload: [String: Any] = [
        "scheduledExact": scheduledExact,
        "scheduledInexact": 0,
        "canceled": canceledKeys.count,
        "failures": failures
      ]
      DispatchQueue.main.async { result(payload) }
    }
  }

  private static func alarm(from item: [String: Any]) -> Alarm? {
    guard let key = item["key"] as? String,
          let title = item["title"] as? String,
          let body = item["body"] as? String,
          let trigger = item["triggerTimeEpochMs"] as? NSNumber else {
      return nil
    }
    return Alarm(key: key, title: title, body: body, triggerEpochMs: trigger.doubleValue)
  }

  private static func content(title: String, body: String, sound: Bool) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = sound ? .default : nil
    return content
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
