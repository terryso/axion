import Foundation

/// 单条 support 数据候选（扫描阶段产出）。字段对齐 Epic「support 数据项字段表」。
///
/// 复用既有类型（Dev Notes「复用清单」）：
/// - `matchEvidence: StorageEvidence` —— 匹配证据（rule/source/confidence）。
/// - `matchConfidence: StorageConfidence` —— 证据置信度（high/medium/low）。
/// - `dataRisk: DataRisk` —— 数据风险（low/medium/high/forbidden）。
///
/// 字段风格对齐 `StorageManifestItem`：显式 snake_case `CodingKeys` + `decodeIfPresent`。
public struct SupportDataItem: Codable, Equatable, Sendable {

    /// 分类。
    public var category: SupportDataCategory
    /// 候选绝对路径（bundle-id 键控精确推导，非 `~/Library` 全量枚举）。
    public var path: String
    /// 字节大小（`totalFileSize ?? fileSize` 口径）。
    public var sizeBytes: Int64
    /// 匹配证据（复用 `StorageEvidence`）。
    public var matchEvidence: StorageEvidence
    /// 证据置信度（复用 `StorageConfidence`，high/medium/low）。
    public var matchConfidence: StorageConfidence
    /// 数据风险（复用 `DataRisk`；forbidden = 云/Keychain，MVP 不处理）。
    public var dataRisk: DataRisk
    /// 是否默认选中（低风险且非低置信度才为 true；高风险恒 false）。
    public var defaultSelected: Bool
    /// 是否需显式逐项确认（高风险 / 共享目录）。
    public var requiresExplicitApproval: Bool

    enum CodingKeys: String, CodingKey {
        case category
        case path
        case sizeBytes = "size_bytes"
        case matchEvidence = "match_evidence"
        case matchConfidence = "match_confidence"
        case dataRisk = "data_risk"
        case defaultSelected = "default_selected"
        case requiresExplicitApproval = "requires_explicit_approval"
    }

    public init(
        category: SupportDataCategory,
        path: String,
        sizeBytes: Int64,
        matchEvidence: StorageEvidence,
        matchConfidence: StorageConfidence,
        dataRisk: DataRisk,
        defaultSelected: Bool,
        requiresExplicitApproval: Bool
    ) {
        self.category = category
        self.path = path
        self.sizeBytes = sizeBytes
        self.matchEvidence = matchEvidence
        self.matchConfidence = matchConfidence
        self.dataRisk = dataRisk
        self.defaultSelected = defaultSelected
        self.requiresExplicitApproval = requiresExplicitApproval
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try c.decodeIfPresent(SupportDataCategory.self, forKey: .category) ?? .cache
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        matchEvidence = try c.decodeIfPresent(StorageEvidence.self, forKey: .matchEvidence) ?? StorageEvidence(rule: "", source: "")
        matchConfidence = try c.decodeIfPresent(StorageConfidence.self, forKey: .matchConfidence) ?? .medium
        dataRisk = try c.decodeIfPresent(DataRisk.self, forKey: .dataRisk) ?? .medium
        defaultSelected = try c.decodeIfPresent(Bool.self, forKey: .defaultSelected) ?? false
        requiresExplicitApproval = try c.decodeIfPresent(Bool.self, forKey: .requiresExplicitApproval) ?? false
    }
}
