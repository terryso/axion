import Foundation

/// 单个计划项。字段对齐 Epic「操作项字段」表。
///
/// `approved` 在本 Story 中恒为 `false` —— 由 `StoragePlanBuilder` 构造时强制，
/// 未经确认不执行任何副作用（执行属 Story 39.2）。
public struct StoragePlanItem: Codable, Equatable, Sendable {

    /// 建议动作。
    public var action: StorageAction
    /// 源路径（必须出现在本次扫描结果中，否则被 builder 拒绝）。
    public var sourcePath: String
    /// 建议目标路径（可选）。
    public var targetPath: String?
    /// 字节大小（builder 就地重新读取）。
    public var sizeBytes: Int64
    /// 分类/动作理由（Agent 提供）。
    public var reason: String
    /// 操作风险等级（builder 回填）。
    public var riskLevel: RiskLevel
    /// 是否已批准（恒为 false）。
    public var approved: Bool
    /// 分类依据。
    public var evidence: StorageEvidence?
    /// 数据风险（builder 回填）。
    public var dataRisk: DataRisk?

    enum CodingKeys: String, CodingKey {
        case action
        case sourcePath = "source_path"
        case targetPath = "target_path"
        case sizeBytes = "size_bytes"
        case reason
        case riskLevel = "risk_level"
        case approved
        case evidence
        case dataRisk = "data_risk"
    }

    public init(
        action: StorageAction,
        sourcePath: String,
        targetPath: String? = nil,
        sizeBytes: Int64 = 0,
        reason: String,
        riskLevel: RiskLevel = .low,
        approved: Bool = false,
        evidence: StorageEvidence? = nil,
        dataRisk: DataRisk? = nil
    ) {
        self.action = action
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.sizeBytes = sizeBytes
        self.reason = reason
        self.riskLevel = riskLevel
        self.approved = approved
        self.evidence = evidence
        self.dataRisk = dataRisk
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decodeIfPresent(StorageAction.self, forKey: .action) ?? .scanOnly
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        targetPath = try c.decodeIfPresent(String.self, forKey: .targetPath)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        riskLevel = try c.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? .low
        approved = try c.decodeIfPresent(Bool.self, forKey: .approved) ?? false
        evidence = try c.decodeIfPresent(StorageEvidence.self, forKey: .evidence)
        dataRisk = try c.decodeIfPresent(DataRisk.self, forKey: .dataRisk)
    }
}
