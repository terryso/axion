import Foundation

import AxionCore

/// chat 入口审批收集器：逐项结构化确认（`approvePlan` / `approveItem` / `cancel`）。
///
/// - 与 run 的「全计划确认」不同：chat 逐项询问，支持子集授权（部分批准）。
/// - DI 闭包注入 I/O（`writeStdout` / `readLine`），便于单元测试 Mock；不直接读写 stdin/stdout。
/// - 子集结果（`approveItem`）经 `resolveOutcome` 触发子集召回（Agent 以子集重调）。
struct ChatApprovalCollector: StorageApproving {

    let writeStdout: @Sendable (String) -> Void
    let readLine: @Sendable () -> String?
    let now: @Sendable () -> String

    init(
        writeStdout: @escaping @Sendable (String) -> Void,
        readLine: @escaping @Sendable () -> String?,
        now: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.writeStdout = writeStdout
        self.readLine = readLine
        self.now = now
    }

    func collect(request: StorageApprovalRequest, policy: SurfacePolicy) async -> StorageApprovalResponse {
        writeStdout("\n" + request.planSummary.renderTerminal() + "\n")

        let groups = Self.makeGroups(from: request.items)
        let selection: Selection
        if groups.count < request.items.count {
            selection = collectGroups(groups)
        } else {
            writeStdout("\n逐项确认：[y] 批准   [n] 跳过   [a] 批准全部剩余   [d] 详情   [q] 取消\n")
            selection = collectItems(request.items, context: nil)
        }

        if selection.cancelled || selection.approvedKeys.isEmpty {
            writeStdout("已取消（无可批准项）。\n")
            return StorageApprovalResponse.cancel(
                operationId: request.operationId,
                surface: request.surface,
                collectedAt: now()
            )
        }

        // typed 二次确认（App 卸载）。
        var typedPayload: String? = nil
        if request.requiresTypedConfirmation,
           let candidates = request.typedConfirmationCandidates,
           let hint = candidates.first, !hint.isEmpty {
            writeStdout("\n该操作将卸载 App，请输入应用名以二次确认（\(hint)）：")
            typedPayload = readLine()
        }

        let action: StorageApprovalAction = (selection.approvedKeys.count == request.items.count) ? .approvePlan : .approveItem
        writeStdout("✓ 已批准 \(selection.approvedKeys.count)/\(request.items.count) 项。\n")
        return StorageApprovalResponse(
            operationId: request.operationId,
            surface: request.surface,
            action: action,
            approvedItemKeys: selection.approvedKeys,
            rejectedItemKeys: selection.rejectedKeys,
            typedConfirmationPayload: typedPayload,
            remoteReserved: nil,
            collectedAt: now()
        )
    }

    // MARK: - Grouped approval

    private struct Selection {
        var approvedKeys: [String] = []
        var rejectedKeys: [String] = []
        var cancelled = false
    }

    private struct ApprovalGroup {
        let label: String
        let action: StorageAction
        let targetPath: String?
        let items: [StorageApprovalItem]

        var totalSizeBytes: Int64 {
            items.reduce(0) { $0 + $1.sizeBytes }
        }

        var riskLevel: RiskLevel {
            items.reduce(.low) { RiskLevel.max($0, $1.riskLevel) }
        }
    }

    private func collectGroups(_ groups: [ApprovalGroup]) -> Selection {
        writeStdout("\n按分组确认：[y] 批准本组   [n] 跳过本组   [i] 逐项查看   [d] 详情   [a] 批准全部剩余   [q] 取消\n")

        var selection = Selection()
        var approveAll = false

        for (index, group) in groups.enumerated() {
            if approveAll {
                selection.approvedKeys.append(contentsOf: group.items.map(\.key))
                continue
            }

            while true {
                writeStdout(renderGroupLine(group, index: index + 1, total: groups.count))
                writeStdout("\n  批准这个分组？[y/n/i/d/a/q]：")
                let raw = normalizedInput()
                switch raw {
                case "y", "yes", "批准":
                    selection.approvedKeys.append(contentsOf: group.items.map(\.key))
                    break
                case "a", "all":
                    approveAll = true
                    selection.approvedKeys.append(contentsOf: group.items.map(\.key))
                    break
                case "i", "item", "items", "逐项":
                    let itemSelection = collectItems(group.items, context: "分组：\(group.label)")
                    if itemSelection.cancelled {
                        selection.cancelled = true
                        return selection
                    }
                    selection.approvedKeys.append(contentsOf: itemSelection.approvedKeys)
                    selection.rejectedKeys.append(contentsOf: itemSelection.rejectedKeys)
                    break
                case "d", "detail", "details", "详情":
                    writeStdout(renderGroupDetails(group))
                    continue
                case "q", "cancel", "取消":
                    selection.cancelled = true
                    return selection
                default:
                    selection.rejectedKeys.append(contentsOf: group.items.map(\.key))
                    break
                }
                break
            }
        }

        return selection
    }

    private func collectItems(_ items: [StorageApprovalItem], context: String?) -> Selection {
        if let context {
            writeStdout("\n逐项查看（\(context)）：[y] 批准   [n] 跳过   [a] 批准全部剩余   [d] 详情   [q] 取消\n")
        }

        var selection = Selection()
        var approveAll = false

        for (index, item) in items.enumerated() {
            if approveAll {
                selection.approvedKeys.append(item.key)
                continue
            }

            while true {
                writeStdout(renderItemLine(item, index: index + 1, total: items.count))
                writeStdout("\n  批准？[y/n/a/d/q]：")
                let raw = normalizedInput()
                switch raw {
                case "y", "yes", "批准":
                    selection.approvedKeys.append(item.key)
                    break
                case "a", "all":
                    approveAll = true
                    selection.approvedKeys.append(item.key)
                    break
                case "d", "detail", "details", "详情":
                    writeStdout(renderItemDetails(item))
                    continue
                case "q", "cancel", "取消":
                    selection.cancelled = true
                    return selection
                default:
                    selection.rejectedKeys.append(item.key)
                    break
                }
                break
            }
        }

        return selection
    }

    // MARK: - Rendering

    private func renderGroupLine(_ group: ApprovalGroup, index: Int, total: Int) -> String {
        let target = group.targetPath.map { " -> \(Self.compactPath($0))" } ?? ""
        return "\n  [\(index)/\(total)] \(group.label) | \(group.items.count) 项 | \(group.action.rawValue)\(target) | \(Self.formatBytes(group.totalSizeBytes)) | risk \(group.riskLevel.rawValue)"
    }

    private func renderGroupDetails(_ group: ApprovalGroup) -> String {
        var lines: [String] = []
        lines.append("\n  详情：\(group.label)")
        for (index, item) in group.items.prefix(12).enumerated() {
            lines.append(Self.renderItemDetailLine(item, index: index + 1))
        }
        if group.items.count > 12 {
            lines.append("    ... 另有 \(group.items.count - 12) 项")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderItemLine(_ item: StorageApprovalItem, index: Int, total: Int) -> String {
        let target = item.targetPath.map { " -> \(Self.compactPath($0))" } ?? ""
        return "\n  [\(index)/\(total)] \(Self.compactPath(item.sourcePath)) | \(item.action.rawValue)\(target) | \(Self.formatBytes(item.sizeBytes)) | risk \(item.riskLevel.rawValue)"
    }

    private func renderItemDetails(_ item: StorageApprovalItem) -> String {
        var lines: [String] = []
        lines.append("\n  详情：")
        lines.append(Self.renderItemDetailLine(item, index: nil))
        if !item.reason.isEmpty {
            lines.append("    reason: \(item.reason)")
        }
        if let evidence = item.evidence {
            lines.append("    evidence: \(evidence.rule) [\(evidence.confidence.rawValue)]")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderItemDetailLine(_ item: StorageApprovalItem, index: Int?) -> String {
        let prefix = index.map { "    \($0)." } ?? "    -"
        let target = item.targetPath.map { " -> \($0)" } ?? ""
        return "\(prefix) \(item.sourcePath)\(target) (\(formatBytes(item.sizeBytes)), \(item.riskLevel.rawValue), \(item.action.rawValue))"
    }

    private func normalizedInput() -> String {
        (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Grouping helpers

    private static func makeGroups(from items: [StorageApprovalItem]) -> [ApprovalGroup] {
        var order: [String] = []
        var buckets: [String: ApprovalGroup] = [:]

        for item in items {
            let category = categoryLabel(from: item)
            let key: String
            let label: String
            if let category {
                key = [
                    "category",
                    category,
                    item.action.rawValue,
                    item.targetPath ?? "",
                ].joined(separator: "\u{1F}")
                label = category
            } else {
                key = "item\u{1F}\(item.key)"
                label = compactPath(item.sourcePath)
            }

            if let existing = buckets[key] {
                buckets[key] = ApprovalGroup(
                    label: existing.label,
                    action: existing.action,
                    targetPath: existing.targetPath,
                    items: existing.items + [item]
                )
            } else {
                order.append(key)
                buckets[key] = ApprovalGroup(
                    label: label,
                    action: item.action,
                    targetPath: item.targetPath,
                    items: [item]
                )
            }
        }

        return order.compactMap { buckets[$0] }
    }

    private static func categoryLabel(from item: StorageApprovalItem) -> String? {
        guard let rule = item.evidence?.rule else { return nil }
        for part in rule.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("category:") else { continue }
            let label = String(trimmed.dropFirst("category:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : label
        }
        return nil
    }

    private static func compactPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024, idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        if idx == 0 { return "\(Int64(value)) \(units[idx])" }
        return String(format: "%.1f %@", value, units[idx])
    }
}
