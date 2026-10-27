import WebKit

extension WKUserContentController {
  /// WKUserContentController 只提供整体清空。抓包、帧率、重载、音频几个桥和 webview_flutter
  /// 的 JavaScriptChannel 包装脚本共用同一个 controller，直接 removeAllUserScripts 会把别人的
  /// 脚本一起删掉：改一次帧率设置，下次刷新页面抓包就没了，而 Dart 端看配置没变不会重下发。
  /// 所以清空后把其余脚本原样挂回去。按源码比对而不是对象身份，userScripts 不保证返回原实例。
  func removeUserScript(_ script: WKUserScript) {
    let remaining = userScripts.filter { $0.source != script.source }
    removeAllUserScripts()
    remaining.forEach { addUserScript($0) }
  }
}
