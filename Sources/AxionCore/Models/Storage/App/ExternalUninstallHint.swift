import Foundation

/// 外部卸载提示（read-only，仅供展示）。来源：pkg receipts / Homebrew cask / vendor uninstaller。
///
/// **绝不执行**（AC #11）：任何 hint 都不改变 Axion 的风险分级与确认流程；探测失败优雅降级为空。
/// `source` 取值：`pkg_receipt` / `homebrew_cask` / `vendor_uninstaller`。
public struct ExternalUninstallHint: Codable, Equatable, Sendable {

    /// 提示来源（`pkg_receipt` / `homebrew_cask` / `vendor_uninstaller`）。
    public var source: String
    /// 人类可读细节。
    public var detail: String
    /// 相关路径（read-only 候选，仅供参考）。
    public var paths: [String]
    /// 置信度（复用 `StorageConfidence`）。
    public var confidence: StorageConfidence

    enum CodingKeys: String, CodingKey {
        case source
        case detail
        case paths
        case confidence
    }

    public init(source: String, detail: String, paths: [String], confidence: StorageConfidence = .medium) {
        self.source = source
        self.detail = detail
        self.paths = paths
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        paths = try c.decodeIfPresent([String].self, forKey: .paths) ?? []
        confidence = try c.decodeIfPresent(StorageConfidence.self, forKey: .confidence) ?? .medium
    }
}
