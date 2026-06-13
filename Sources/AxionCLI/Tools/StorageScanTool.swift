import Foundation
import OpenAgentSDK

import AxionCore

/// `storage_scan` —— 只读扫描 Agent 工具（CLI 端 `ToolProtocol`，bare name `storage_scan`）。
///
/// 扫描给定根目录，返回基于「代码提取的文件信号 + 目录上下文」的候选分组与大文件列表。
/// **不读取文件正文**（AC #8），**不产生任何文件副作用**（AC #6）。symlink 不跟随，
/// bundle/library 折叠为单条目。分类由 Agent 基于 `storage-organize-hint` 提示完成，
/// 通过 `propose_storage_plan` 提交，不在本工具内做最终业务分类。
///
/// 扫描器通过 `StorageScanning` 协议注入，便于测试用 `MockStorageScanner`。
final class StorageScanTool: ToolProtocol, Sendable {

    let name = "storage_scan"
    let description = "扫描指定目录（默认用户目录：~/Downloads、~/Desktop、~/Documents），返回底层文件信号分组（按类型）与大文件列表，用于磁盘占用分析与整理建议。只读，不移动/删除任何文件。开发缓存目录（node_modules/.build/DerivedData/.venv 等）会折叠为 developer_cache 根目录候选，不展开内部文件。参数：roots(绝对路径数组，可选，默认用户目录)、min_size_mb(大文件阈值，单位 MB(十进制 10^6)，可选，缺省时回退配置阈值默认 1 GiB = 1073741824)、include_hidden(是否含隐藏文件，默认 false)、exclude_paths(额外排除路径数组，可选)。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "roots": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Absolute paths to scan. Defaults to user Downloads/Desktop/Documents.",
            ],
            "min_size_mb": [
                "type": "integer",
                "description": "Large-file threshold in decimal MB (1 MB = 1_000_000 bytes). When omitted, falls back to the configured large_file_threshold_bytes (default 1 GiB = 1_073_741_824).",
            ],
            "include_hidden": [
                "type": "boolean",
                "description": "Include hidden entries (default false).",
            ],
            "exclude_paths": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Additional absolute paths to exclude (appended to built-in set).",
            ],
        ],
        "required": [],
    ]
    let isReadOnly = true

    private let scanner: StorageScanning
    private let config: StorageConfig

    init(scanner: StorageScanning, config: StorageConfig = .default) {
        self.scanner = scanner
        self.config = config
    }

    func call(input: Any, context: ToolContext) async -> ToolResult {
        let toolUseId = context.toolUseId
        guard let params = input as? [String: Any] else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "invalid_input",
                message: "Input must be a JSON object",
                suggestion: "Pass a JSON object with optional 'roots', 'min_size_mb', 'include_hidden', 'exclude_paths'"
            )
        }

        // roots：显式 > 默认用户目录
        let roots: [URL]
        if let rawRoots = params["roots"] as? [String], !rawRoots.isEmpty {
            roots = rawRoots.map { URL(fileURLWithPath: $0) }
        } else {
            roots = Self.defaultRoots()
        }
        if roots.isEmpty {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "no_roots",
                message: "No scan roots provided and no default user directories found",
                suggestion: "Provide 'roots' as an array of absolute directory paths"
            )
        }

        // min_size_mb：可选，缺省回退 config 阈值
        let minSizeBytes: Int64?
        if let mb = params["min_size_mb"] as? Int {
            minSizeBytes = Int64(mb) * 1_000_000
        } else if let mb = params["min_size_mb"] as? Double {
            minSizeBytes = Int64(mb * 1_000_000)
        } else {
            minSizeBytes = config.largeFileThresholdBytes
        }

        let includeHidden = (params["include_hidden"] as? Bool) ?? false
        let extraExcludes = (params["exclude_paths"] as? [String]) ?? []
        let excludedPaths = config.excludedPaths + extraExcludes

        let request = ScanRequest(
            roots: roots,
            minSizeBytes: minSizeBytes,
            includeHidden: includeHidden,
            excludedPaths: excludedPaths,
            excludeSymlinkTargets: true,
            maxFilesPerGroup: config.maxFilesPerGroup
        )

        let result: ScanResult
        do {
            result = try await scanner.scan(request)
        } catch is CancellationError {
            // Agent 中断（ESC/Ctrl+C）→ scanner 抛 CancellationError。_streamTask 已 cancel，
            // turn 将以 .cancelled 结束；返回最小非 error 结果，避免 agent 基于半截数据继续、
            // 也避免误报 scan_failed。
            return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
                try encoder.encode(ScanResponse(
                    status: "cancelled",
                    roots: roots.map { $0.path },
                    groups: [],
                    largeFiles: [],
                    skippedCount: 0,
                    excludedNotes: [],
                    summary: "Scan cancelled."
                ))
            }
        } catch {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "scan_failed",
                message: "Scan failed: \(error.localizedDescription)",
                suggestion: "Check that the scan roots are accessible directories"
            )
        }

        let summary = "Scanned \(roots.count) root(s); \(result.largeFiles.count) large file(s) >= \(StoragePlanFormatter.formatBytes(minSizeBytes ?? 0)); \(result.groups.count) group(s); \(result.skippedCount) skipped."

        return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(ScanResponse(
                status: "ok",
                roots: roots.map { $0.path },
                groups: result.groups,
                largeFiles: result.largeFiles,
                skippedCount: result.skippedCount,
                excludedNotes: result.excludedNotes,
                summary: summary
            ))
        }
    }

    // MARK: - Helpers

    /// 默认扫描根：存在的用户目录（Downloads / Desktop / Documents）。
    static func defaultRoots(home: String = NSHomeDirectory()) -> [URL] {
        let fm = FileManager.default
        return ["Downloads", "Desktop", "Documents"]
            .map { home + "/\($0)" }
            .filter { fm.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}

/// `storage_scan` 的工具响应（snake_case，面向 Agent / 远程入口）。
private struct ScanResponse: Encodable {
    let status: String
    let roots: [String]
    let groups: [FileSignalGroup]
    let largeFiles: [FileSignal]
    let skippedCount: Int
    let excludedNotes: [String]
    let summary: String

    enum CodingKeys: String, CodingKey {
        case status, roots, groups
        case largeFiles = "large_files"
        case skippedCount = "skipped_count"
        case excludedNotes = "excluded_notes"
        case summary
    }
}
