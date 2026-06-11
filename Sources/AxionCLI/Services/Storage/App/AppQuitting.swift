import Foundation

/// App 退出抽象（Protocol，测试注入 `MockAppQuitter` 用）。
///
/// **graceful only**：`terminate` 发送 terminate Apple Event 让 App 正常退出；超时仍未退出
/// 返回 `false`，**不 force-kill**（避免破坏未保存数据）。返回 `true` 表示 App 已退出或本未运行。
protocol AppQuitting: Sendable {
    func terminate(bundleIdentifier: String) async -> Bool
}
