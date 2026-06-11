import Foundation

/// 审批动作（surface 无关）。run / chat / telegram 三个入口共享同一套语义，
/// 由 `StorageApproving` 各入口实现（`AxionCLI`）负责把各自交互结果归一为本枚举。
///
/// - approvePlan：批准整个请求（全部 items）
/// - approveItem：仅批准子集（`approvedItemKeys` 严格小于全部）
/// - rejectItem：用户明确否决部分项
/// - cancel：取消（含安全默认：非 TTY / 远程 MVP / typed 失败等场景）
public enum StorageApprovalAction: String, Sendable, Equatable, Codable {
    case approvePlan = "approve_plan"
    case approveItem = "approve_item"
    case rejectItem = "reject_item"
    case cancel
}
