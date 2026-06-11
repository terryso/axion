import Foundation

/// 卸载模式（对齐 Epic「卸载模式」）。rawValue 用 snake_case。
///
/// - `scanOnly`：仅扫描 App + support 候选，不执行。
/// - `uninstallAppOnly`：仅移除 App bundle，不动 support 数据。
/// - `uninstallWithSupportReview`：默认模式——扫描 App + support 候选供审查。
/// - `reviewSupportData`：仅审查 support 数据候选（不卸载 App）。
/// - `cleanApprovedSupportData`：清理已批准的 support 数据（不卸载 App）。
public enum AppUninstallMode: String, Sendable, Equatable, Codable {
    case scanOnly = "scan_only"
    case uninstallAppOnly = "uninstall_app_only"
    case uninstallWithSupportReview = "uninstall_with_support_review"
    case reviewSupportData = "review_support_data"
    case cleanApprovedSupportData = "clean_approved_support_data"
}
