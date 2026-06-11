import Foundation

import AxionCore

/// 文件系统扫描的抽象（Protocol），便于测试注入 `MockStorageScanner`。
///
/// 实现仅读取元数据（不读取文件正文，满足 AC #8），不产生任何副作用
/// （不移动、不删除、不创建目录，满足 AC #6）。
protocol StorageScanning: Sendable {
    func scan(_ request: ScanRequest) async throws -> ScanResult
}

/// 扫描请求。自包含：根、阈值、隐藏开关、额外排除、symlink 行为、分组截断。
struct ScanRequest: Sendable, Equatable {

    /// 扫描根目录（绝对路径）。
    let roots: [URL]
    /// 大文件阈值（字节）。`nil` 表示不产出 `largeFiles`（无法定义「大」）。
    let minSizeBytes: Int64?
    /// 是否纳入隐藏条目。默认 `false`。
    let includeHidden: Bool
    /// 额外排除路径（绝对路径，叠加在内置集之上）。
    let excludedPaths: [String]
    /// 是否排除 symlink 目标（仅记录链接本身）。**保留字段**：AC #2 要求 symlink
    /// 恒不跟随其目标，扫描实现始终把 symlink 当作路径项处理（`FileManager.enumerator`
    /// 默认即不跟随），**忽略**本字段取值——保留它是为向前兼容 ScanRequest 契约，
    /// 不代表支持「跟随 symlink」的扫描模式。
    let excludeSymlinkTargets: Bool
    /// 每个分组保留的代表文件数上限。
    let maxFilesPerGroup: Int

    init(
        roots: [URL],
        minSizeBytes: Int64? = nil,
        includeHidden: Bool = false,
        excludedPaths: [String] = [],
        excludeSymlinkTargets: Bool = true,
        maxFilesPerGroup: Int = 50
    ) {
        self.roots = roots
        self.minSizeBytes = minSizeBytes
        self.includeHidden = includeHidden
        self.excludedPaths = excludedPaths
        self.excludeSymlinkTargets = excludeSymlinkTargets
        self.maxFilesPerGroup = maxFilesPerGroup
    }
}

/// 扫描结果。工具/入口面向契约，使用显式 snake_case `CodingKeys`。
struct ScanResult: Codable, Equatable, Sendable {

    /// 按 `FileKind` 聚合的底层信号分组（降序）。
    let groups: [FileSignalGroup]
    /// 大文件列表（`sizeBytes >= minSizeBytes`，降序）。
    let largeFiles: [FileSignal]
    /// 被跳过的条目数（含排除与访问失败）。
    let skippedCount: Int
    /// 扫描备注（缺失根、排除汇总等）。
    let excludedNotes: [String]

    enum CodingKeys: String, CodingKey {
        case groups
        case largeFiles = "large_files"
        case skippedCount = "skipped_count"
        case excludedNotes = "excluded_notes"
    }

    init(groups: [FileSignalGroup], largeFiles: [FileSignal], skippedCount: Int, excludedNotes: [String]) {
        self.groups = groups
        self.largeFiles = largeFiles
        self.skippedCount = skippedCount
        self.excludedNotes = excludedNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([FileSignalGroup].self, forKey: .groups) ?? []
        largeFiles = try c.decodeIfPresent([FileSignal].self, forKey: .largeFiles) ?? []
        skippedCount = try c.decodeIfPresent(Int.self, forKey: .skippedCount) ?? 0
        excludedNotes = try c.decodeIfPresent([String].self, forKey: .excludedNotes) ?? []
    }
}
