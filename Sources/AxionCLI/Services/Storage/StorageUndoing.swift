import Foundation

import AxionCore

/// 撤销抽象（Protocol，测试注入 `MockStorageUndoer` 用）。
///
/// 按 manifest 逆向恢复：`move` 移回、`trash` 从废纸篓移回、空目录移除。无法恢复项给出
/// 明确原因，不影响其余可恢复项（best-effort，逐项独立）。返回 `nil` 表示无可撤销 manifest
/// （由调用工具转 `no_undoable_manifest` 错误）。
protocol StorageUndoing: Sendable {
    func undo(_ request: UndoRequest) async -> UndoResult?
}

/// 撤销请求。
struct UndoRequest: Sendable, Equatable {

    /// 操作 ID；`nil` 表示撤销最近一次可撤销操作（`mostRecentUndoable`）。
    let operationId: String?
    /// manifest 存储目录。
    let storageOpsDir: String
    /// 主目录（路径展开用）。
    let homeDirectory: String

    init(operationId: String?, storageOpsDir: String, homeDirectory: String) {
        self.operationId = operationId
        self.storageOpsDir = storageOpsDir
        self.homeDirectory = homeDirectory
    }
}

/// 撤销结果。
struct UndoResult: Sendable, Equatable {

    /// 写回后的 manifest（含 `undoneAt` + `undoResults`）。
    let manifest: StorageManifest
    /// 成功恢复计数。
    let restored: Int
    /// 无法恢复计数。
    let notRestored: Int
    /// 跳过计数（原项 scanOnly / failed / skipped，无可恢复对象）。
    let skipped: Int
}
