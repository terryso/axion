import ApplicationServices
import CoreGraphics
import Foundation

/// 权限检查结果状态
enum PermissionStatus: Equatable {
    case granted
    case notGranted
    case unknown
}

/// PermissionChecker — 检查 macOS 系统级权限状态。
/// 注意：CLI 进程本身检查权限状态是**指示性**的 — 实际需要 Helper App 获得授权。
/// setup 命令检查的是系统级状态并引导用户。
struct PermissionChecker {

    /// 检查 Accessibility（辅助功能）权限。
    /// 使用 AXIsProcessTrusted()（ApplicationServices 框架）。
    static func checkAccessibility() -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return trusted ? .granted : .notGranted
    }

    /// 检查屏幕录制权限。
    /// 使用 CGPreflightScreenCaptureAccess()（CoreGraphics 框架，macOS 10.15+）。
    static func checkScreenRecording() -> PermissionStatus {
        if #available(macOS 10.15, *) {
            let hasAccess = CGPreflightScreenCaptureAccess()
            return hasAccess ? .granted : .notGranted
        }
        return .unknown
    }
}
