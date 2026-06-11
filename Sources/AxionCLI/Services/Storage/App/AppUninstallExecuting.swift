import Foundation

import AxionCore

/// App 卸载执行抽象（Protocol，测试注入 `MockAppUninstallExecutor` / 真实 executor 用）。
///
/// 入参即「已批准集」——App bundle 是否卸载 + 已批准的 support 数据项。审批决策由调用方 / 入口
/// 在调用执行**之前**完成（AC #14，typed 确认强制由 39.4 入口统一）。executor 执行前对 bundle 与
/// 每项 support 数据**独立纵深校验**（AC #12），违规项不执行 + 记 `errors`。
protocol AppUninstallExecuting: Sendable {
    func execute(_ request: AppUninstallExecuteRequest) async -> AppUninstallExecuteResult
}

/// App 卸载执行请求（解析自 `execute_app_uninstall` 工具入参）。
///
/// `storageOpsDir` 为审计/契约字段（对齐 `ExecuteRequest`）；manifest 持久化走 executor 注入的
/// `StorageManifestStore`（与 `ExecuteStoragePlanTool` 同模式）。`searchRoots` 用于 bundle 纵深校验。
struct AppUninstallExecuteRequest: Sendable, Equatable {

    /// 操作 ID。
    let operationId: String
    /// 入口。
    let surface: StorageSurface
    /// 目标 App。
    let app: AppCandidate
    /// 是否卸载 App bundle（false = 仅清理 support 数据）。
    let uninstallBundle: Bool
    /// 已批准的 support 数据项（执行集；低置信度项不应在此）。
    let supportDataItems: [SupportDataItem]
    /// 卸载根（用于 bundle 纵深校验，AC #12 路径 ∈ searchRoots）。
    let searchRoots: [URL]
    /// 用户原始任务（写入 manifest 供审计）。
    let userRequest: String?
    /// 主目录（路径展开用）。
    let homeDirectory: String
    /// manifest 存储目录（审计/契约字段；持久化走注入的 manifestStore）。
    let storageOpsDir: String
}

/// App 卸载执行结果。
struct AppUninstallExecuteResult: Sendable, Equatable {

    /// 最终 manifest（已落盘）。
    let manifest: StorageManifest
    /// 成功项计数。
    let succeeded: Int
    /// 跳过项计数（拒绝/未运行等）。
    let skipped: Int
    /// 失败项计数。
    let failed: Int
}
