import Foundation

struct MCPStatusFormatter {
    static let defaultMaxItems = 15

    static func renderAll(
        _ entries: [MCPStatusEntry],
        terminalWidth _: Int = 100
    ) -> String {
        var lines = [summaryTitle(entries) + ":", ""]
        let nameWidth = min(max((entries.map(\.name.count).max() ?? 0) + 2, 16), 32)
        let typeWidth = 7
        let sourceWidth = 9

        for entry in entries {
            let name = pad(truncate(sanitize(entry.name), width: nameWidth), width: nameWidth)
            let type = pad(truncate(sanitize(entry.type), width: typeWidth), width: typeWidth)
            let source = pad(truncate(sanitize(entry.source), width: sourceWidth), width: sourceWidth)
            lines.append("  \(name)\(type)\(source)\(sanitize(entry.state))")
            for detail in entry.details {
                lines.append("    \(sanitize(detail))")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n") + "\n"
    }

    static func renderList(
        _ entries: [MCPStatusEntry],
        selectedIndex: Int? = nil,
        maxItems: Int = defaultMaxItems,
        startIndex: Int = 0,
        includeControls: Bool = true,
        numbered: Bool = false,
        terminalWidth: Int = 100
    ) -> String {
        var lines: [String] = []
        let pageSize = max(1, maxItems)
        let safeStartIndex = normalizedStartIndex(startIndex, total: entries.count, pageSize: pageSize)
        let shownEntries = Array(entries.dropFirst(safeStartIndex).prefix(pageSize))
        let controls = includeControls ? "  ↑/↓ 选择 · Enter 详情 · q/Esc 退出" : ""
        lines.append(titleLine(entries, shownCount: shownEntries.count, maxItems: pageSize, startIndex: safeStartIndex) + controls)

        if shownEntries.isEmpty {
            lines.append("  未找到 MCP server")
        } else {
            let nameWidth = min(max(shownEntries.map(\.name.count).max() ?? 0, 14), 30)
            lines.append(formatHeaderLine(nameWidth: nameWidth))
            for (index, entry) in shownEntries.enumerated() {
                let absoluteIndex = safeStartIndex + index
                let marker = numbered ? "\(absoluteIndex + 1)." : (selectedIndex == absoluteIndex ? "▶" : " ")
                lines.append(formatItemLine(entry, marker: marker, nameWidth: nameWidth))
            }
        }

        if entries.count > shownEntries.count {
            let rangeStart = shownEntries.isEmpty ? 0 : safeStartIndex + 1
            let rangeEnd = safeStartIndex + shownEntries.count
            let actionHint = includeControls ? "继续按 ↑/↓ 翻页" : "使用 /mcp --all 查看完整配置"
            lines.append("  显示 \(rangeStart)-\(rangeEnd) / \(entries.count)；\(actionHint)")
        }

        if numbered {
            lines.append("  非交互模式：仅显示列表；使用 /mcp --all 查看完整配置。")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderDetail(
        _ entry: MCPStatusEntry,
        terminalWidth: Int = 100
    ) -> String {
        let detailWidth = max(24, terminalWidth - 4)
        var lines = [
            "MCP server 详情  b 返回列表 · q/Esc 退出",
            "  名称: \(sanitize(entry.name))",
            "  状态: \(sanitize(entry.state))",
            "  来源: \(sanitize(entry.source))",
            "  类型: \(sanitize(entry.type))",
            "  生效: \(entry.isReady ? "是" : "否")",
            "  命名空间: \(namespacePreview(for: entry))",
        ]

        if entry.details.isEmpty {
            lines.append("  详情: -")
        } else {
            lines.append("  配置:")
            for detail in entry.details {
                lines.append("    \(truncate(sanitize(detail), width: detailWidth))")
            }
        }

        lines.append("  安全: headers/env 只显示 key，值已脱敏。")
        return lines.joined(separator: "\n") + "\n"
    }

    static func titleLine(
        _ entries: [MCPStatusEntry],
        shownCount: Int,
        maxItems: Int,
        startIndex: Int = 0
    ) -> String {
        let pageSize = max(1, maxItems)
        let shown = entries.count > pageSize && shownCount > 0
            ? "，显示 \(startIndex + 1)-\(startIndex + shownCount)"
            : ""
        return "\(summaryTitle(entries))\(shown)"
    }

    private static func summaryTitle(_ entries: [MCPStatusEntry]) -> String {
        let readyCount = entries.filter(\.isReady).count
        return "MCP servers（\(readyCount) ready，\(entries.count) total）"
    }

    private static func formatHeaderLine(nameWidth: Int) -> String {
        let name = pad("Server", width: nameWidth)
        let type = pad("Type", width: 7)
        let source = pad("Source", width: 9)
        return "  \(name)  \(type)  \(source)  Status"
    }

    private static func formatItemLine(_ entry: MCPStatusEntry, marker: String, nameWidth: Int) -> String {
        let name = pad(truncate(sanitize(entry.name), width: nameWidth), width: nameWidth)
        let type = pad(truncate(sanitize(entry.type), width: 7), width: 7)
        let source = pad(truncate(sanitize(entry.source), width: 9), width: 9)
        return "\(marker) \(name)  \(type)  \(source)  \(sanitize(entry.state))"
    }

    private static func namespacePreview(for entry: MCPStatusEntry) -> String {
        guard entry.isReady, !entry.name.isEmpty, !entry.name.contains("__") else {
            return "-"
        }
        return "mcp__\(sanitize(entry.name))__<tool>"
    }

    private static func normalizedStartIndex(_ startIndex: Int, total: Int, pageSize: Int) -> Int {
        guard total > 0 else { return 0 }
        let lastStart = max(0, total - pageSize)
        return min(max(0, startIndex), lastStart)
    }

    private static func pad(_ text: String, width: Int) -> String {
        text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private static func truncate(_ text: String, width: Int) -> String {
        guard text.count > width else { return text }
        guard width > 1 else { return String(text.prefix(width)) }
        return String(text.prefix(width - 1)) + "…"
    }

    private static func sanitize(_ raw: String) -> String {
        let raw = ChatComposer.stripAnsi(raw)
        var output = ""
        var lastWasSpace = false
        for scalar in raw.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint || CharacterSet.controlCharacters.contains(scalar) {
                if !lastWasSpace {
                    output.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            let char = Character(scalar)
            if char.isWhitespace {
                if !lastWasSpace {
                    output.append(" ")
                    lastWasSpace = true
                }
            } else {
                output.append(char)
                lastWasSpace = false
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
