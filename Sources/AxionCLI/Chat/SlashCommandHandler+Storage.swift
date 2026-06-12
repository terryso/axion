import Foundation

extension SlashCommandHandler {
    private static let storageDefaultScanRoots = "~/Downloads, ~/Desktop, ~/Documents"
    private static let storageCommonLargeRoots = [
        "~/Downloads",
        "~/Desktop",
        "~/Documents",
        "~/Movies",
        "~/Pictures",
        "~/Music",
        "~/Applications",
    ]

    static func handleStorageHelp() -> String {
        """
        存储整理命令:
          /storage scan [path]             只读扫描目录；不指定时扫描 ~/Downloads、~/Desktop、~/Documents
          /storage organize [path]         生成整理计划；不指定时整理 ~/Downloads，执行前逐项确认
          /storage large [path] [size]     查找大文件；不指定 path 时扫描常用用户目录，默认 1GB
          /storage large [size]            例如 /storage large 500MB
          /storage large --home [size]     扫描整个主目录，使用内置系统/缓存/隐藏目录排除
          /storage undo [operation_id]     撤销一次已执行的存储整理；不指定时撤销最近一次

        示例:
          /storage large
          /storage large 500MB
          /storage large ~/Projects 200MB
          /storage large --home 1GB
          /storage organize ~/Downloads

        """
    }

    static func buildStorageTask(argument: String?) -> String? {
        let trimmed = argument?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let commandPart = parts.first else { return nil }

        let subcommand = String(commandPart).lowercased()
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch subcommand {
        case "help", "-h", "--help", "?":
            return nil
        case "scan":
            return buildStorageScanTask(path: nonEmpty(rest))
        case "organize":
            return buildStorageOrganizeTask(path: nonEmpty(rest) ?? "~/Downloads")
        case "large":
            guard let options = parseStorageLargeOptions(rest) else { return nil }
            return buildStorageLargeTask(options: options)
        case "undo":
            return buildStorageUndoTask(operationId: nonEmpty(rest))
        default:
            return nil
        }
    }

    private static func buildStorageScanTask(path: String?) -> String {
        let scope = path ?? storageDefaultScanRoots
        let rootsInstruction: String
        if let path {
            rootsInstruction = "调用 `storage_scan` 时将 `roots` 设为这个目录展开后的绝对路径：\(path)。"
        } else {
            rootsInstruction = "调用 `storage_scan` 时不传 `roots`，使用工具默认目录：\(storageDefaultScanRoots)。"
        }

        return """
        请在交互模式下执行一次只读存储扫描。

        目标范围：\(scope)

        要求：
        - \(rootsInstruction)
        - 只调用 `storage_scan`；只读取文件元数据，不读取文件正文。
        - 重点关注 `developer_cache` 分组；`node_modules`、`.build`、`DerivedData`、`.venv` 等会作为可重建目录根折叠显示，适合作为安全清理候选。
        - 不调用 `propose_storage_plan`、`execute_storage_plan` 或任何会移动/删除文件的工具。
        - 输出按空间占用排序的摘要，突出大文件、文件类型分组、被跳过的目录和可整理线索。
        """
    }

    private static func buildStorageOrganizeTask(path: String) -> String {
        """
        请在交互模式下整理这个目录：\(path)

        流程：
        1. 先调用 `storage_scan`，`roots` 使用该目录展开后的绝对路径。
        2. 根据扫描结果生成少量高置信分类建议，再调用 `propose_storage_plan`，`surface` 使用 `chat`，`scan_roots` 必须与扫描根一致。
        3. 先展示计划摘要和风险点；只有用户明确确认后，才调用 `execute_storage_plan`。
        4. `execute_storage_plan` 必须继续使用相同 `operation_id` 和 `scan_roots`，并依赖交互模式的逐项审批。

        安全约束：
        - 不读取文件正文。
        - 对 `node_modules`、`.build`、`DerivedData`、`.venv` 等 `developer_cache` 目录，只能把目录根作为整体清理候选，不要选择内部子路径。
        - 不永久删除文件；清理动作只能走系统废纸篓。
        - 不绕过审批，不处理计划外路径。
        """
    }

    private static func buildStorageLargeTask(options: StorageLargeOptions) -> String {
        let thresholdLine: String
        if let threshold = options.threshold {
            thresholdLine = "调用 `storage_scan` 时传 `min_size_mb: \(threshold.minSizeMB)`（用户输入阈值：\(threshold.display)）。"
        } else {
            thresholdLine = "调用 `storage_scan` 时不传 `min_size_mb`，使用配置默认大文件阈值（默认 1GB 级别）。"
        }

        let scopeLine: String
        let rootsLine: String
        let homeSafetyLine: String
        switch options.scope {
        case .common:
            let roots = storageCommonLargeRoots.joined(separator: ", ")
            scopeLine = "目标范围：常用用户目录（\(roots)）。"
            rootsLine = "调用 `storage_scan` 时将 `roots` 设为这些目录展开后的绝对路径；不存在或不可访问的目录在结果中说明即可。"
            homeSafetyLine = "如果用户随后想扩大范围，建议使用 `/storage large --home [size]`。"
        case .home:
            scopeLine = "目标范围：整个用户主目录 `~`。"
            rootsLine = "调用 `storage_scan` 时将 `roots` 设为当前用户主目录展开后的绝对路径。"
            homeSafetyLine = "必须保留内置系统、缓存、隐藏目录和受保护路径排除；不要主动放宽 `~/Library` 等保护规则。"
        case .path(let path):
            scopeLine = "目标范围：\(path)。"
            rootsLine = "调用 `storage_scan` 时将 `roots` 设为这个目录展开后的绝对路径。"
            homeSafetyLine = "如果目录不存在或不可访问，直接说明原因。"
        }

        return """
        请查找大文件，帮助我决定后续是否清理。

        \(scopeLine)
        \(thresholdLine)

        要求：
        - \(rootsLine)
        - \(homeSafetyLine)
        - 只调用 `storage_scan`；只读取文件元数据，不读取文件正文。
        - 按文件大小降序列出大文件，包含路径、大小、修改时间和是否来自 Downloads 等信号。
        - 本轮只列出候选，不调用 `propose_storage_plan` 或 `execute_storage_plan`。
        - 不移动、不删除、不归档文件；后续清理必须由用户明确指定文件或确认整理计划后再走审批。
        """
    }

    private static func buildStorageUndoTask(operationId: String?) -> String {
        if let operationId {
            return """
            请撤销这个存储整理操作：\(operationId)

            调用 `undo_storage_op`，传入 `operation_id: "\(operationId)"`。执行后汇总恢复结果、失败项和仍需用户手动处理的路径。
            """
        }

        return """
        请撤销最近一次可撤销的存储整理操作。

        调用 `undo_storage_op`，不传 `operation_id`。执行后汇总恢复结果、失败项和仍需用户手动处理的路径。
        """
    }

    private static func parseStorageLargeOptions(_ raw: String) -> StorageLargeOptions? {
        let tokens = raw
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var scanHome = false
        var threshold: StorageLargeThreshold?
        var pathTokens: [String] = []

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "--home" {
                scanHome = true
                index += 1
                continue
            }
            if token.hasPrefix("--") {
                return nil
            }

            if index + 1 < tokens.count,
               isPositiveNumberToken(token),
               isStorageSizeUnitToken(tokens[index + 1]),
               let parsed = parseStorageLargeThreshold(token + tokens[index + 1]) {
                guard threshold == nil else { return nil }
                threshold = parsed
                index += 2
                continue
            }

            if let parsed = parseStorageLargeThreshold(token) {
                guard threshold == nil else { return nil }
                threshold = parsed
                index += 1
                continue
            }
            pathTokens.append(token)
            index += 1
        }

        let path = nonEmpty(pathTokens.joined(separator: " "))
        if scanHome && path != nil {
            return nil
        }

        let scope: StorageLargeScope
        if scanHome {
            scope = .home
        } else if let path {
            scope = .path(path)
        } else {
            scope = .common
        }

        return StorageLargeOptions(scope: scope, threshold: threshold)
    }

    private static func parseStorageLargeThreshold(_ token: String) -> StorageLargeThreshold? {
        let lower = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }

        let units: [(suffix: String, mbMultiplier: Double)] = [
            ("tib", 1024 * 1024),
            ("tb", 1_000_000),
            ("t", 1_000_000),
            ("gib", 1024),
            ("gb", 1000),
            ("g", 1000),
            ("mib", 1.048576),
            ("mb", 1),
            ("m", 1),
            ("kb", 0.001),
            ("k", 0.001),
        ]

        for unit in units {
            guard lower.hasSuffix(unit.suffix) else { continue }
            let numberPart = String(lower.dropLast(unit.suffix.count))
            guard let value = Double(numberPart), value > 0 else { return nil }
            return StorageLargeThreshold(
                display: token,
                minSizeMB: max(1, Int((value * unit.mbMultiplier).rounded(.up)))
            )
        }

        guard let value = Double(lower), value > 0 else { return nil }
        return StorageLargeThreshold(display: "\(token)MB", minSizeMB: max(1, Int(value.rounded(.up))))
    }

    private static func isPositiveNumberToken(_ token: String) -> Bool {
        guard let value = Double(token.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return value > 0
    }

    private static func isStorageSizeUnitToken(_ token: String) -> Bool {
        let lower = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["tib", "tb", "t", "gib", "gb", "g", "mib", "mb", "m", "kb", "k"].contains(lower)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct StorageLargeOptions {
        let scope: StorageLargeScope
        let threshold: StorageLargeThreshold?
    }

    private enum StorageLargeScope {
        case common
        case home
        case path(String)
    }

    private struct StorageLargeThreshold {
        let display: String
        let minSizeMB: Int
    }
}
