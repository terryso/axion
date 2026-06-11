import Foundation

/// 文件信号分组（按 `FileKind` 或目录簇聚合）。
/// 大组的 `files` 可截断（仅保留代表性条目），`count`/`totalSizeBytes` 始终反映全组。
public struct FileSignalGroup: Codable, Equatable, Sendable {

    /// 分组标签（通常为 `FileKind` 原始值或目录名）。
    public var label: String
    /// 全组文件总数（不受 `files` 截断影响）。
    public var count: Int
    /// 全组总字节数。
    public var totalSizeBytes: Int64
    /// 代表性文件信号（大组可截断）。
    public var files: [FileSignal]
    /// 该组共性信号摘要（如出现频率高的扩展名、来源标记等）。
    public var commonSignals: [String]

    enum CodingKeys: String, CodingKey {
        case label, count
        case totalSizeBytes = "total_size_bytes"
        case files
        case commonSignals = "common_signals"
    }

    public init(
        label: String,
        count: Int,
        totalSizeBytes: Int64,
        files: [FileSignal],
        commonSignals: [String] = []
    ) {
        self.label = label
        self.count = count
        self.totalSizeBytes = totalSizeBytes
        self.files = files
        self.commonSignals = commonSignals
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        totalSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .totalSizeBytes) ?? 0
        files = try c.decodeIfPresent([FileSignal].self, forKey: .files) ?? []
        commonSignals = try c.decodeIfPresent([String].self, forKey: .commonSignals) ?? []
    }
}
