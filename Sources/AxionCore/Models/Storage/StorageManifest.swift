import Foundation

/// 整理执行 manifest 主体。字段对齐 Epic「Manifest 字段」表，面向工具 / 入口 / 远程契约，
/// 使用显式 snake_case `CodingKeys`（与 39.1 的 `StoragePlan` 一致）。撤销扩展字段
/// （`undoneAt` / `undoResults`）向前兼容：旧 manifest 解码时为 nil，39.3/39.4 新增字段
/// 亦通过 `decodeIfPresent` 回退。
public struct StorageManifest: Codable, Equatable, Sendable {

    /// 操作 ID（由 Agent 从 `propose_storage_plan` 透传，便于审计关联）。
    public var operationId: String
    /// 创建时间（ISO8601，executor 写草稿时生成）。
    public var createdAt: String
    /// 完成时间（ISO8601，executor 置终态时回填）。
    public var completedAt: String?
    /// 入口（run/chat/telegram）。
    public var surface: StorageSurface
    /// 用户原始任务（可选，写入供审计）。
    public var userRequest: String?
    /// 审批摘要（如 `"3 items approved via run"`，executor 生成）。
    public var approvedByUser: String?
    /// 已执行的项（succeeded/failed/skipped；违规项不在此，而在 `errors`）。
    public var items: [StorageManifestItem]
    /// manifest 级状态。
    public var status: StorageOpStatus
    /// 违规项 / 错误汇总（纵深防御丢弃的项记于此）。
    public var errors: [String]
    /// 人类可读摘要（含 succeeded/skipped/failed 计数）。
    public var summary: String?

    // MARK: - 撤销扩展（向前兼容）

    /// 撤销时间（ISO8601，撤销写回时填）。
    public var undoneAt: String?
    /// 逐项撤销结果。
    public var undoResults: [StorageUndoResult]?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case surface
        case userRequest = "user_request"
        case approvedByUser = "approved_by_user"
        case items
        case status
        case errors
        case summary
        case undoneAt = "undone_at"
        case undoResults = "undo_results"
    }

    public init(
        operationId: String,
        createdAt: String,
        completedAt: String? = nil,
        surface: StorageSurface,
        userRequest: String? = nil,
        approvedByUser: String? = nil,
        items: [StorageManifestItem] = [],
        status: StorageOpStatus,
        errors: [String] = [],
        summary: String? = nil,
        undoneAt: String? = nil,
        undoResults: [StorageUndoResult]? = nil
    ) {
        self.operationId = operationId
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.surface = surface
        self.userRequest = userRequest
        self.approvedByUser = approvedByUser
        self.items = items
        self.status = status
        self.errors = errors
        self.summary = summary
        self.undoneAt = undoneAt
        self.undoResults = undoResults
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try c.decodeIfPresent(String.self, forKey: .operationId) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        surface = try c.decodeIfPresent(StorageSurface.self, forKey: .surface) ?? .run
        userRequest = try c.decodeIfPresent(String.self, forKey: .userRequest)
        approvedByUser = try c.decodeIfPresent(String.self, forKey: .approvedByUser)
        items = try c.decodeIfPresent([StorageManifestItem].self, forKey: .items) ?? []
        status = try c.decodeIfPresent(StorageOpStatus.self, forKey: .status) ?? .planned
        errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        undoneAt = try c.decodeIfPresent(String.self, forKey: .undoneAt)
        undoResults = try c.decodeIfPresent([StorageUndoResult].self, forKey: .undoResults)
    }
}
