import Foundation

/// Manifest 级状态机。执行流程：`planned`（草稿落盘）→ `executing`（首项开始）→
/// `completed`（全部成功）/ `partiallyFailed`（≥1 项失败）。`cancelled` 预留给未来中断路径
/// （本 Story executor 主体不主动置 `cancelled`，但模型必须支持）。撤销不改变 `status`，
/// 只追加 `undoneAt` / `undoResults`。
public enum StorageOpStatus: String, Sendable, Equatable, Codable {
    case planned
    case executing
    case completed
    case partiallyFailed = "partially_failed"
    case cancelled
}
