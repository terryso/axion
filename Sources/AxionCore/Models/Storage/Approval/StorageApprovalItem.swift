import Foundation

/// 审批项（计划项级，与工具级 `ApprovalDecision` 不同轴）。字段对齐 AC #1。
///
/// `key` 为 `sourcePath`（或 App 场景下的 bundlePath）的唯一键，用于子集授权与去重。
/// 字段风格对齐 `StorageManifestItem` / `SupportDataItem`：显式 snake_case `CodingKeys` + `decodeIfPresent`。
public struct StorageApprovalItem: Codable, Equatable, Sendable {

    /// 唯一键（sourcePath 或 bundlePath）。
    public var key: String
    /// 动作（复用 `StorageAction`）。
    public var action: StorageAction
    /// 源路径。
    public var sourcePath: String
    /// 目标路径（move / createDirectory 时存在）。
    public var targetPath: String?
    /// 字节大小。
    public var sizeBytes: Int64
    /// 操作风险（复用 `RiskLevel`）。
    public var riskLevel: RiskLevel
    /// 数据风险（复用 `DataRisk`；缺失时由 surface policy 决定是否默认放行）。
    public var dataRisk: DataRisk?
    /// 分类理由（人类可读）。
    public var reason: String
    /// 是否需显式逐项确认（高风险 / 共享目录）。
    public var requiresExplicitApproval: Bool
    /// 证据（复用 `StorageEvidence`）。
    public var evidence: StorageEvidence?

    enum CodingKeys: String, CodingKey {
        case key
        case action
        case sourcePath = "source_path"
        case targetPath = "target_path"
        case sizeBytes = "size_bytes"
        case riskLevel = "risk_level"
        case dataRisk = "data_risk"
        case reason
        case requiresExplicitApproval = "requires_explicit_approval"
        case evidence
    }

    public init(
        key: String,
        action: StorageAction,
        sourcePath: String,
        targetPath: String? = nil,
        sizeBytes: Int64,
        riskLevel: RiskLevel,
        dataRisk: DataRisk? = nil,
        reason: String,
        requiresExplicitApproval: Bool,
        evidence: StorageEvidence? = nil
    ) {
        self.key = key
        self.action = action
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.sizeBytes = sizeBytes
        self.riskLevel = riskLevel
        self.dataRisk = dataRisk
        self.reason = reason
        self.requiresExplicitApproval = requiresExplicitApproval
        self.evidence = evidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        action = try c.decodeIfPresent(StorageAction.self, forKey: .action) ?? .scanOnly
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        targetPath = try c.decodeIfPresent(String.self, forKey: .targetPath)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        riskLevel = try c.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? .low
        dataRisk = try c.decodeIfPresent(DataRisk.self, forKey: .dataRisk)
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        requiresExplicitApproval = try c.decodeIfPresent(Bool.self, forKey: .requiresExplicitApproval) ?? false
        evidence = try c.decodeIfPresent(StorageEvidence.self, forKey: .evidence)
    }
}
