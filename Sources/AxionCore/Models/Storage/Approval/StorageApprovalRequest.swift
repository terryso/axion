import Foundation

/// 审批请求（surface 无关）。字段见 AC #1。run / chat / telegram 共用。
public struct StorageApprovalRequest: Codable, Equatable, Sendable {

    /// 操作 ID（与 execute 工具的 operation_id 对齐）。
    public var operationId: String
    /// 入口。
    public var surface: StorageSurface
    /// 计划摘要（聚合 + 三种渲染）。
    public var planSummary: PlanSummary
    /// 待审批项。
    public var items: [StorageApprovalItem]
    /// 是否需 typed 确认（如 App 卸载）。
    public var requiresTypedConfirmation: Bool
    /// 用户原始请求（可选，便于上下文展示）。
    public var userRequest: String?
    /// typed 确认可接受值（App 名 / bundle id；execute_app_uninstall 卸载 bundle 时填充）。
    ///
    /// 使 `resolveOutcome` 成为完全可单测的纯函数（AC #4）：把「该输入什么」纳入请求，
    /// 而非在执行端隐式推断。任一非空 candidate 命中即通过。
    public var typedConfirmationCandidates: [String]?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case surface
        case planSummary = "plan_summary"
        case items
        case requiresTypedConfirmation = "requires_typed_confirmation"
        case userRequest = "user_request"
        case typedConfirmationCandidates = "typed_confirmation_candidates"
    }

    public init(
        operationId: String,
        surface: StorageSurface,
        planSummary: PlanSummary,
        items: [StorageApprovalItem],
        requiresTypedConfirmation: Bool,
        userRequest: String? = nil,
        typedConfirmationCandidates: [String]? = nil
    ) {
        self.operationId = operationId
        self.surface = surface
        self.planSummary = planSummary
        self.items = items
        self.requiresTypedConfirmation = requiresTypedConfirmation
        self.userRequest = userRequest
        self.typedConfirmationCandidates = typedConfirmationCandidates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try c.decodeIfPresent(String.self, forKey: .operationId) ?? ""
        surface = try c.decodeIfPresent(StorageSurface.self, forKey: .surface) ?? .run
        planSummary = try c.decodeIfPresent(PlanSummary.self, forKey: .planSummary)
            ?? PlanSummary.build(operationId: "", surface: .run, items: [], reversible: true, requiresTypedConfirmation: false)
        items = try c.decodeIfPresent([StorageApprovalItem].self, forKey: .items) ?? []
        requiresTypedConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requiresTypedConfirmation) ?? false
        userRequest = try c.decodeIfPresent(String.self, forKey: .userRequest)
        typedConfirmationCandidates = try c.decodeIfPresent([String].self, forKey: .typedConfirmationCandidates)
    }
}
