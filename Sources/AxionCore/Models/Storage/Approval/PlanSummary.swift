import Foundation

/// 计划摘要（surface 无关）。聚合风险/动作分布，并提供三种渲染：
/// `renderTerminal()`（run/chat）、`renderJSON()`（--json）、`renderRemoteCompressed(maxChars:)`（telegram 预留）。
public struct PlanSummary: Codable, Equatable, Sendable {

    /// 操作 ID。
    public var operationId: String
    /// 入口。
    public var surface: StorageSurface
    /// 计划级聚合风险（取最高）。
    public var riskLevel: RiskLevel
    /// 项总数。
    public var totalItems: Int
    /// 按动作计数。
    public var countsByAction: [StorageAction: Int]
    /// 按风险计数。
    public var countsByRisk: [RiskLevel: Int]
    /// 是否可恢复（仅 trash / 移动到废纸篓场景为 true）。
    public var reversible: Bool
    /// 是否需 typed 确认。
    public var requiresTypedConfirmation: Bool
    /// 前 N 项（按大小降序，便于摘要展示）。
    public var topItems: [StorageApprovalItem]
    /// 因 topN 截断的项数。
    public var truncatedCount: Int
    /// 人类可读摘要（预渲染，供终端/远程复用）。
    public var humanReadableSummary: String

    /// 默认展示的前 N 项。
    public static let defaultTopN: Int = 8

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case surface
        case riskLevel = "risk_level"
        case totalItems = "total_items"
        case countsByAction = "counts_by_action"
        case countsByRisk = "counts_by_risk"
        case reversible
        case requiresTypedConfirmation = "requires_typed_confirmation"
        case topItems = "top_items"
        case truncatedCount = "truncated_count"
        case humanReadableSummary = "human_readable_summary"
    }

    public init(
        operationId: String,
        surface: StorageSurface,
        riskLevel: RiskLevel,
        totalItems: Int,
        countsByAction: [StorageAction: Int],
        countsByRisk: [RiskLevel: Int],
        reversible: Bool,
        requiresTypedConfirmation: Bool,
        topItems: [StorageApprovalItem],
        truncatedCount: Int,
        humanReadableSummary: String
    ) {
        self.operationId = operationId
        self.surface = surface
        self.riskLevel = riskLevel
        self.totalItems = totalItems
        self.countsByAction = countsByAction
        self.countsByRisk = countsByRisk
        self.reversible = reversible
        self.requiresTypedConfirmation = requiresTypedConfirmation
        self.topItems = topItems
        self.truncatedCount = truncatedCount
        self.humanReadableSummary = humanReadableSummary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try c.decodeIfPresent(String.self, forKey: .operationId) ?? ""
        surface = try c.decodeIfPresent(StorageSurface.self, forKey: .surface) ?? .run
        riskLevel = try c.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? .low
        totalItems = try c.decodeIfPresent(Int.self, forKey: .totalItems) ?? 0
        countsByAction = try c.decodeIfPresent([StorageAction: Int].self, forKey: .countsByAction) ?? [:]
        countsByRisk = try c.decodeIfPresent([RiskLevel: Int].self, forKey: .countsByRisk) ?? [:]
        reversible = try c.decodeIfPresent(Bool.self, forKey: .reversible) ?? true
        requiresTypedConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requiresTypedConfirmation) ?? false
        topItems = try c.decodeIfPresent([StorageApprovalItem].self, forKey: .topItems) ?? []
        truncatedCount = try c.decodeIfPresent(Int.self, forKey: .truncatedCount) ?? 0
        humanReadableSummary = try c.decodeIfPresent(String.self, forKey: .humanReadableSummary) ?? ""
    }

    // MARK: - Build

    /// 由原始 items 聚合构造摘要。
    public static func build(
        operationId: String,
        surface: StorageSurface,
        items: [StorageApprovalItem],
        reversible: Bool,
        requiresTypedConfirmation: Bool,
        topN: Int = defaultTopN
    ) -> PlanSummary {
        var countsByAction: [StorageAction: Int] = [:]
        var countsByRisk: [RiskLevel: Int] = [:]
        var aggregated: RiskLevel = .low
        for item in items {
            countsByAction[item.action, default: 0] += 1
            countsByRisk[item.riskLevel, default: 0] += 1
            aggregated = RiskLevel.max(aggregated, item.riskLevel)
        }
        let sorted = items.sorted { $0.sizeBytes > $1.sizeBytes }
        let limit = max(0, topN)
        let top = Array(sorted.prefix(limit))
        let truncated = max(0, items.count - top.count)
        let summary = composeHumanReadable(
            surface: surface, operationId: operationId, riskLevel: aggregated,
            totalItems: items.count, countsByAction: countsByAction, countsByRisk: countsByRisk,
            reversible: reversible, requiresTypedConfirmation: requiresTypedConfirmation, top: top, truncated: truncated
        )
        return PlanSummary(
            operationId: operationId,
            surface: surface,
            riskLevel: aggregated,
            totalItems: items.count,
            countsByAction: countsByAction,
            countsByRisk: countsByRisk,
            reversible: reversible,
            requiresTypedConfirmation: requiresTypedConfirmation,
            topItems: top,
            truncatedCount: truncated,
            humanReadableSummary: summary
        )
    }

    // MARK: - Render

    /// 终端多行渲染（run/chat 用）。
    public func renderTerminal() -> String {
        var lines: [String] = []
        lines.append("📦 存储整理计划（surface: \(surface.rawValue)）")
        lines.append("   操作 ID: \(operationId.isEmpty ? "-" : operationId)")
        lines.append("   风险等级: \(riskEmoji(riskLevel)) \(riskLevel.rawValue)  |  可恢复: \(reversible ? "✓（废纸篓）" : "✗")  |  需 typed 确认: \(requiresTypedConfirmation ? "✓" : "✗")")
        let actionDesc = countsByAction.isEmpty
            ? "-"
            : countsByAction.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ", ")
        let riskDesc = countsByRisk.isEmpty
            ? "-"
            : countsByRisk.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ", ")
        lines.append("   共 \(totalItems) 项  |  动作: \(actionDesc)  |  风险: \(riskDesc)")
        if !topItems.isEmpty {
            lines.append("   前 \(topItems.count) 项（按大小降序）:")
            for (idx, item) in topItems.enumerated() {
                let target = item.targetPath.map { " → \($0)" } ?? ""
                lines.append("     \(idx + 1). [\(item.action.rawValue)] \(item.sourcePath)\(target)  (\(formatBytes(item.sizeBytes)), \(riskEmoji(item.riskLevel)) \(item.riskLevel.rawValue)) — \(item.reason)")
            }
            if truncatedCount > 0 {
                lines.append("     … 另有 \(truncatedCount) 项未列出")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// JSON 渲染（即其 Codable 编码，键排序稳定以便断言）。
    public func renderJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    /// 远程压缩渲染：把 `humanReadableSummary` 分页为 ≤ `maxChars` 的短串数组（telegram 预留）。
    ///
    /// 首页不带游标；后续页在串首以 `[pN/M]` 标注，并随消息携带 `detailCursor`（由调用方写入 `RemoteApprovalReserved`）。
    public func renderRemoteCompressed(maxChars: Int = 900) -> [String] {
        guard !humanReadableSummary.isEmpty else { return [""] }
        let limit = max(64, maxChars)
        let pages = paginate(humanReadableSummary, maxChars: limit)
        if pages.count <= 1 { return pages }
        return pages.enumerated().map { idx, page in
            "[p\(idx + 1)/\(pages.count)] " + page
        }
    }

    // MARK: - Private helpers

    private static func composeHumanReadable(
        surface: StorageSurface, operationId: String, riskLevel: RiskLevel,
        totalItems: Int, countsByAction: [StorageAction: Int], countsByRisk: [RiskLevel: Int],
        reversible: Bool, requiresTypedConfirmation: Bool,
        top: [StorageApprovalItem], truncated: Int
    ) -> String {
        var parts: [String] = []
        parts.append("[\(surface.rawValue)] op=\(operationId.isEmpty ? "-" : operationId) risk=\(riskLevel.rawValue) items=\(totalItems) reversible=\(reversible) typed=\(requiresTypedConfirmation)")
        if !countsByAction.isEmpty {
            parts.append("actions: " + countsByAction.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ","))
        }
        if !top.isEmpty {
            parts.append("top: " + top.map { "\($0.action.rawValue) \($0.sourcePath)(\(formatBytes($0.sizeBytes)))" }.joined(separator: "; "))
        }
        if truncated > 0 { parts.append("…+\(truncated)") }
        return parts.joined(separator: " | ")
    }

    private func riskEmoji(_ r: RiskLevel) -> String {
        switch r {
        case .low: return "🟢"
        case .medium: return "🟡"
        case .high: return "🔴"
        }
    }

    /// 按字符数切分（不破坏多字节字符：按 Character 迭代）。
    private func paginate(_ text: String, maxChars: Int) -> [String] {
        var pages: [String] = []
        var current = ""
        for ch in text {
            if current.count + 1 > maxChars {
                pages.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [""] : pages
    }
}

fileprivate func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = Double(bytes)
    var i = 0
    while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
    let rounded = (v * 10).rounded() / 10
    return rounded.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(v)) \(units[i])"
        : "\(rounded) \(units[i])"
}
