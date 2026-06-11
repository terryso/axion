import Foundation

/// 存储整理计划。字段对齐 Epic「计划字段」表。包含 `surface` 字段使其与入口解耦
/// （`run`/`chat`/future `telegram`）。本 Story 仅产出计划，不执行。
public struct StoragePlan: Codable, Equatable, Sendable {

    /// 计划操作 ID（运行时生成）。
    public var operationId: String
    /// 入口（run/chat/telegram）。
    public var surface: StorageSurface
    /// 计划项（已校验、approved=false）。
    public var items: [StoragePlanItem]
    /// 计划级风险（取 item 最高级）。
    public var riskLevel: RiskLevel
    /// 是否需要用户确认（恒为 true）。
    public var requiresConfirmation: Bool
    /// 是否可撤销（移动/废纸篓可撤销；本 Story 不出现永久删除）。
    public var reversible: Bool
    /// 人类可读摘要。
    public var summary: String
    /// 创建时间（ISO8601 字符串）。
    public var createdAt: String
    /// 被拒绝的提议说明（向前兼容；39.2 manifest 可消费）。
    public var excludedNotes: [String]?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case surface, items
        case riskLevel = "risk_level"
        case requiresConfirmation = "requires_confirmation"
        case reversible
        case summary
        case createdAt = "created_at"
        case excludedNotes = "excluded_notes"
    }

    public init(
        operationId: String,
        surface: StorageSurface,
        items: [StoragePlanItem],
        riskLevel: RiskLevel,
        requiresConfirmation: Bool = true,
        reversible: Bool = true,
        summary: String,
        createdAt: String,
        excludedNotes: [String]? = nil
    ) {
        self.operationId = operationId
        self.surface = surface
        self.items = items
        self.riskLevel = riskLevel
        self.requiresConfirmation = requiresConfirmation
        self.reversible = reversible
        self.summary = summary
        self.createdAt = createdAt
        self.excludedNotes = excludedNotes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try c.decodeIfPresent(String.self, forKey: .operationId) ?? ""
        surface = try c.decodeIfPresent(StorageSurface.self, forKey: .surface) ?? .run
        items = try c.decodeIfPresent([StoragePlanItem].self, forKey: .items) ?? []
        riskLevel = try c.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? .low
        requiresConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? true
        reversible = try c.decodeIfPresent(Bool.self, forKey: .reversible) ?? true
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        excludedNotes = try c.decodeIfPresent([String].self, forKey: .excludedNotes)
    }
}
