import Foundation
import AppKit

import AxionCore

/// App 退出实现（`import AppKit`，AxionCLI 直接用 AppKit 是既有惯例）。
///
/// **graceful only**：取匹配 `bundleIdentifier` 的 `NSRunningApplication`，发 `terminate()`
/// （graceful，发 quit Apple Event），轮询 `isTerminated` 带超时（默认 8s）。超时仍未退出
/// → 返回 `false`，**不 force-kill**（避免破坏未保存数据，AC #3）。未运行视为已退出。
///
/// 注：Story 原文写「`requestTermination()` / `activationState`」，但 `NSRunningApplication`
/// 无 `requestTermination()`（graceful 方法是 `terminate()`），退出态判定用 `isTerminated`
/// （非 `activationState`，见 Task 2 修正）。此处照实际 AppKit API 实现。
final class AppQuitter: AppQuitting, Sendable {

    /// graceful 退出宽限期（秒）；超时返回 false，不 force-kill。
    private static let timeoutSeconds: TimeInterval = 8
    /// 轮询间隔（秒）。
    private static let pollIntervalSeconds: TimeInterval = 0.2

    init() {}

    func terminate(bundleIdentifier: String) async -> Bool {
        guard !bundleIdentifier.isEmpty else { return true }

        let matching = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }
        // 未运行 → 视为已退出（无需终止）。
        if matching.isEmpty { return true }

        // graceful：逐个发 terminate Apple Event（不 forceTerminate）。
        for app in matching {
            app.terminate()
        }

        // 轮询 isTerminated 带超时。
        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)
        while Date() < deadline {
            let stillRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
            }
            if !stillRunning { return true }
            try? await Task.sleep(nanoseconds: UInt64(Self.pollIntervalSeconds * 1_000_000_000))
        }
        return false
    }
}
