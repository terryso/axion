import Foundation

/// 卸载目标的候选 App（发现阶段产出）。字段对齐 Epic「App 识别字段表」。
///
/// `matchConfidence` 用 `AppMatchConfidence`（用户输入→候选匹配），与
/// `SupportDataItem.matchConfidence`（`StorageConfidence`，证据置信度）区分。
/// 字段风格对齐 `StorageManifest`：显式 snake_case `CodingKeys` + `decodeIfPresent` 回退。
public struct AppCandidate: Codable, Equatable, Sendable {

    /// 显示名（取 `CFBundleDisplayName` ?? `CFBundleName`）。
    public var displayName: String
    /// bundle id（`CFBundleIdentifier`）。
    public var bundleIdentifier: String
    /// bundle 绝对路径（如 `/Applications/Foo.app`）。
    public var bundlePath: String
    /// 版本（`CFBundleShortVersionString` ?? `CFBundleVersion`）。
    public var version: String
    /// 团队标识（签名信息，读取失败为 nil，不阻塞发现）。
    public var teamIdentifier: String?
    /// bundle 体积（字节，近似；目录走 `totalFileSize`）。
    public var sizeBytes: Int64
    /// 是否正在运行（`activationState != .terminated`）。
    public var isRunning: Bool
    /// 是否受系统保护（系统/Apple/MDM/系统目录）。
    public var isSystemProtected: Bool
    /// 用户输入→候选匹配置信度。
    public var matchConfidence: AppMatchConfidence

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bundleIdentifier = "bundle_identifier"
        case bundlePath = "bundle_path"
        case version
        case teamIdentifier = "team_identifier"
        case sizeBytes = "size_bytes"
        case isRunning = "is_running"
        case isSystemProtected = "is_system_protected"
        case matchConfidence = "match_confidence"
    }

    public init(
        displayName: String,
        bundleIdentifier: String,
        bundlePath: String,
        version: String,
        teamIdentifier: String? = nil,
        sizeBytes: Int64,
        isRunning: Bool,
        isSystemProtected: Bool,
        matchConfidence: AppMatchConfidence
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.version = version
        self.teamIdentifier = teamIdentifier
        self.sizeBytes = sizeBytes
        self.isRunning = isRunning
        self.isSystemProtected = isSystemProtected
        self.matchConfidence = matchConfidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
        bundlePath = try c.decodeIfPresent(String.self, forKey: .bundlePath) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        teamIdentifier = try c.decodeIfPresent(String.self, forKey: .teamIdentifier)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        isRunning = try c.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        isSystemProtected = try c.decodeIfPresent(Bool.self, forKey: .isSystemProtected) ?? false
        matchConfidence = try c.decodeIfPresent(AppMatchConfidence.self, forKey: .matchConfidence) ?? .low
    }
}
