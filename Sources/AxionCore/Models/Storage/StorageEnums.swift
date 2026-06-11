import Foundation

/// 计划项可执行的动作枚举。本 Story 仅声明模型；`move`/`trash`/`createDirectory`/
/// `uninstallApp` 的**执行**由 Story 39.2 / 39.3 实现。本 Story 中默认动作恒为 `scanOnly`。
public enum StorageAction: String, Sendable, Equatable, Codable {
    case move
    case trash
    case createDirectory = "create_directory"
    case uninstallApp = "uninstall_app"
    case scanOnly = "scan_only"
}

/// 风险等级。
public enum RiskLevel: String, Sendable, Equatable, Codable {
    case low
    case medium
    case high

    /// 取两者中更高的一级（用于计划级风险聚合）。
    public static func max(_ a: RiskLevel, _ b: RiskLevel) -> RiskLevel {
        let order: [RiskLevel] = [.low, .medium, .high]
        return order.firstIndex(of: a)! >= order.firstIndex(of: b)! ? a : b
    }
}

/// 计划产出面对的入口（与入口解耦）。
public enum StorageSurface: String, Sendable, Equatable, Codable {
    case run
    case chat
    case telegram
}

/// 数据风险（独立于操作风险）。`forbidden` 为后续 Story 预留（如系统目录永久删除）。
public enum DataRisk: String, Sendable, Equatable, Codable {
    case low
    case medium
    case high
    case forbidden
}

/// 证据置信度。
public enum StorageConfidence: String, Sendable, Equatable, Codable {
    case high
    case medium
    case low
}

/// 分类依据：说明某项分类使用了哪些规则/来源与置信度。
public struct StorageEvidence: Codable, Equatable, Sendable {
    /// 命中的规则（如 `large_file`、`installer_kind`、`from_downloads`）。
    public var rule: String
    /// 信号来源（Agent 给出的理由或扫描信号描述）。
    public var source: String
    /// 置信度。
    public var confidence: StorageConfidence

    enum CodingKeys: String, CodingKey {
        case rule, source, confidence
    }

    public init(rule: String, source: String, confidence: StorageConfidence = .medium) {
        self.rule = rule
        self.source = source
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rule = try c.decodeIfPresent(String.self, forKey: .rule) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        confidence = try c.decodeIfPresent(StorageConfidence.self, forKey: .confidence) ?? .medium
    }
}
