import Foundation

import AxionCore

/// 整理执行抽象（Protocol，测试注入 `MockStorageExecutor` 用）。
///
/// 仅执行「已确定要执行的项」——审批决策由调用方 / 入口在调用**之前**完成
/// （`run` 走终端确认，交互模式走逐项确认；39.4 再统一 `approvePlan`/`approveItem`
/// 结构化语义）。本协议不接触真实 Helper、不发网络、不依赖 SDK Agent 循环。
protocol StorageExecuting: Sendable {
    func execute(_ request: ExecuteRequest) async -> ExecuteResult
}

/// 单项执行请求（解析自 `execute_storage_plan` 工具入参）。
struct ExecutionItem: Sendable, Equatable {

    /// 动作（白名单由 executor 强制：仅 `move`/`trash`/`createDirectory`/`scanOnly`；
    /// `uninstallApp` / 任何 `delete` 一律拒绝）。
    let action: StorageAction
    /// 主操作数路径（绝对路径；`move`/`trash`/`scanOnly` 指已存在源，`createDirectory` 指待创建目录）。
    let source: String
    /// 目标路径（`move` 的目的地）。
    let target: String?
    /// 分类 / 动作理由。
    let reason: String?
    /// 透传证据。
    let evidence: StorageEvidence?
    /// 字节大小（Agent 入参；executor 执行前就源路径重新读取覆盖之，不信此值）。
    let sizeBytes: Int64

    init(
        action: StorageAction,
        source: String,
        target: String? = nil,
        reason: String? = nil,
        evidence: StorageEvidence? = nil,
        sizeBytes: Int64 = 0
    ) {
        self.action = action
        self.source = source
        self.target = target
        self.reason = reason
        self.evidence = evidence
        self.sizeBytes = sizeBytes
    }
}

/// 执行请求。
struct ExecuteRequest: Sendable, Equatable {

    /// 操作 ID（Agent 从 `propose_storage_plan` 透传）。
    let operationId: String
    /// 入口。
    let surface: StorageSurface
    /// 扫描根（用于重校验 source 范围）。
    let scanRoots: [URL]
    /// 用户原始任务（写入 manifest）。
    let userRequest: String?
    /// 待执行项。
    let items: [ExecutionItem]
    /// 主目录（路径展开用）。
    let homeDirectory: String
    /// manifest 存储目录。
    let storageOpsDir: String

    init(
        operationId: String,
        surface: StorageSurface,
        scanRoots: [URL],
        userRequest: String? = nil,
        items: [ExecutionItem],
        homeDirectory: String,
        storageOpsDir: String
    ) {
        self.operationId = operationId
        self.surface = surface
        self.scanRoots = scanRoots
        self.userRequest = userRequest
        self.items = items
        self.homeDirectory = homeDirectory
        self.storageOpsDir = storageOpsDir
    }
}

/// 执行结果。
struct ExecuteResult: Sendable, Equatable {

    /// 最终 manifest（已落盘）。
    let manifest: StorageManifest
    /// 成功项计数。
    let succeeded: Int
    /// 跳过项计数（noop / scanOnly）。
    let skipped: Int
    /// 失败项计数。
    let failed: Int
}
