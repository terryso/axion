import Foundation

/// 存储整理配置（AxionConfig.storage）。使用部分解码：缺失字段回退到 `.default`。
public struct StorageConfig: Codable, Equatable, Sendable {

    /// 大文件阈值（字节），默认 1 GiB（1_073_741_824）。
    public var largeFileThresholdBytes: Int64
    /// 用户额外排除路径（叠加在内置排除集之上）。
    public var excludedPaths: [String]
    /// 每个分组保留的代表文件数上限。
    public var maxFilesPerGroup: Int
    /// 存储操作目录（供 Story 39.2 manifest 使用；本 Story 仅定义）。
    public var storageOpsDir: String

    public static let `default` = StorageConfig(
        largeFileThresholdBytes: 1_073_741_824,
        excludedPaths: [],
        maxFilesPerGroup: 50,
        storageOpsDir: "~/.axion/storage-ops/"
    )

    enum CodingKeys: String, CodingKey {
        case largeFileThresholdBytes = "large_file_threshold_bytes"
        case excludedPaths = "excluded_paths"
        case maxFilesPerGroup = "max_files_per_group"
        case storageOpsDir = "storage_ops_dir"
    }

    public init(
        largeFileThresholdBytes: Int64 = 1_073_741_824,
        excludedPaths: [String] = [],
        maxFilesPerGroup: Int = 50,
        storageOpsDir: String = "~/.axion/storage-ops/"
    ) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.excludedPaths = excludedPaths
        self.maxFilesPerGroup = maxFilesPerGroup
        self.storageOpsDir = storageOpsDir
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        largeFileThresholdBytes = try c.decodeIfPresent(Int64.self, forKey: .largeFileThresholdBytes)
            ?? Self.default.largeFileThresholdBytes
        excludedPaths = try c.decodeIfPresent([String].self, forKey: .excludedPaths)
            ?? Self.default.excludedPaths
        maxFilesPerGroup = try c.decodeIfPresent(Int.self, forKey: .maxFilesPerGroup)
            ?? Self.default.maxFilesPerGroup
        storageOpsDir = try c.decodeIfPresent(String.self, forKey: .storageOpsDir)
            ?? Self.default.storageOpsDir
    }
}
