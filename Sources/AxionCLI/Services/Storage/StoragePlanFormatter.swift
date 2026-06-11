import Foundation

import AxionCore

/// 计划 / 扫描结果的纯函数格式化器（终端 + JSON）。
///
/// 遵循反模式 #20（Chat/ 纯函数 + DI）：不依赖 SDK 类型、不做 I/O、不持有状态。
/// 被 `run`（终端 / `--json`）与交互（`chat`）入口共享调用，保证两端输出一致（AC #5）。
enum StoragePlanFormatter {

    /// 终端渲染：分组列表 + 风险标记 + 摘要（`run` / `chat` 共用）。
    static func render(_ plan: StoragePlan) -> String {
        var lines: [String] = []
        lines.append("📦 Storage Plan: \(plan.operationId)")
        lines.append("   surface: \(plan.surface.rawValue) | risk: \(plan.riskLevel.rawValue) | items: \(plan.items.count) | reversible: \(plan.reversible)")
        lines.append("   \(plan.summary)")
        lines.append("")

        if plan.items.isEmpty {
            lines.append("   (no items — nothing proposed)")
        } else {
            for item in plan.items {
                let approved = item.approved ? "[x]" : "[ ]"
                let risk = riskMarker(item.riskLevel)
                lines.append("   \(approved) \(risk) \(item.action.rawValue)  \(item.sourcePath)")
                if let target = item.targetPath, !target.isEmpty {
                    lines.append("        -> \(target)")
                }
                lines.append("        reason: \(item.reason)  size: \(formatBytes(item.sizeBytes))")
                if let ev = item.evidence {
                    lines.append("        evidence: \(ev.rule) [\(ev.confidence.rawValue)]")
                }
            }
        }

        if let notes = plan.excludedNotes, !notes.isEmpty {
            lines.append("")
            lines.append("   ⚠ Rejected proposals (\(notes.count)):")
            for n in notes { lines.append("     - \(n)") }
        }

        lines.append("")
        lines.append("   ⏸ All items approved=false — nothing is executed without your confirmation.")
        return lines.joined(separator: "\n")
    }

    /// 扫描结果终端摘要（`run` / `chat` 共用）。
    static func render(_ result: ScanResult) -> String {
        var lines: [String] = []
        lines.append("🔍 Scan: \(result.groups.count) group(s), \(result.largeFiles.count) large file(s), \(result.skippedCount) skipped")
        for g in result.groups {
            lines.append("   • \(g.label): \(g.count) file(s), \(formatBytes(g.totalSizeBytes))")
        }
        if !result.largeFiles.isEmpty {
            lines.append("")
            lines.append("   Large files:")
            let shown = result.largeFiles.prefix(20)
            for f in shown {
                lines.append("     \(formatBytes(f.sizeBytes))  \(f.path)")
            }
            if result.largeFiles.count > 20 {
                lines.append("     ... +\(result.largeFiles.count - 20) more")
            }
        }
        if !result.excludedNotes.isEmpty {
            lines.append("")
            lines.append("   Notes: \(result.excludedNotes.joined(separator: "; "))")
        }
        return lines.joined(separator: "\n")
    }

    /// JSON 渲染（`--json` / 远程入口），snake_case（与 `StoragePlan` 的 `CodingKeys` 一致）。
    static func renderJSON(_ plan: StoragePlan) -> String {
        guard let data = try? axionSortedEncoder.encode(plan),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Helpers

    private static func riskMarker(_ level: RiskLevel) -> String {
        switch level {
        case .high: return "[HIGH]"
        case .medium: return "[MED] "
        case .low: return "[LOW] "
        }
    }

    /// 字节数的人类可读格式（十进制，`run`/`chat`/`storage_scan` 摘要共用）。
    static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1000, idx < units.count - 1 {
            value /= 1000
            idx += 1
        }
        return idx == 0 ? "\(Int64(value))\(units[idx])" : String(format: "%.1f%@", value, units[idx])
    }
}
