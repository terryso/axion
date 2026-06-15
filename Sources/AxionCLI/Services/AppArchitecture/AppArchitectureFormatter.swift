import Foundation

struct AppArchitectureFormatter {
    static let defaultInteractiveMaxItems = 20

    static func render(_ result: AppArchitectureScanResult, terminalWidth: Int = 120) -> String {
        var lines: [String] = []
        lines.append(summaryLine(result))

        if !result.options.includeAllArchitectures {
            lines.append("  默认只显示 Intel-only 风险项；使用 --all 查看 Universal / Apple Silicon / Unknown。")
        }

        let visible = result.visibleItems()
        if visible.isEmpty {
            lines.append(result.options.includeAllArchitectures
                ? "  未找到匹配的软件。"
                : "  未发现 Intel-only 匹配项。"
            )
        } else {
            let nameWidth = min(max(visible.map(\.name.count).max() ?? 0, 16), 30)
            let archWidth = 16
            let categoryWidth = 14
            let sourceWidth = 12
            let pathWidth = max(24, terminalWidth - nameWidth - archWidth - categoryWidth - sourceWidth - 12)
            lines.append(headerLine(
                nameWidth: nameWidth,
                archWidth: archWidth,
                categoryWidth: categoryWidth,
                sourceWidth: sourceWidth
            ))
            for item in visible {
                lines.append(itemLine(
                    item,
                    nameWidth: nameWidth,
                    archWidth: archWidth,
                    categoryWidth: categoryWidth,
                    sourceWidth: sourceWidth,
                    pathWidth: pathWidth
                ))
            }
        }

        let visibleTotal = result.visibleTotalCount()
        if result.options.limit > 0, visibleTotal > visible.count {
            lines.append("  显示 \(visible.count) / \(visibleTotal)；使用 --limit 调整显示数量。")
        }

        for warning in result.warnings {
            lines.append("  提示: \(sanitize(warning))")
        }

        if !result.options.includeSystemApps {
            lines.append("  提示: 使用 --system 可包含 /System/Applications。")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderList(
        _ result: AppArchitectureScanResult,
        selectedIndex: Int? = nil,
        maxItems: Int = defaultInteractiveMaxItems,
        startIndex: Int = 0,
        includeControls: Bool = true,
        numbered: Bool = false,
        terminalWidth _: Int = 100
    ) -> String {
        var lines: [String] = []
        let visible = result.visibleItems()
        let pageSize = max(1, maxItems)
        let safeStartIndex = normalizedStartIndex(startIndex, total: visible.count, pageSize: pageSize)
        let shownItems = Array(visible.dropFirst(safeStartIndex).prefix(pageSize))
        let controls = includeControls ? "  ↑/↓ 选择 · Enter 详情 · q/Esc 退出" : ""
        lines.append(titleLine(
            result: result,
            shownCount: shownItems.count,
            maxItems: pageSize,
            startIndex: safeStartIndex
        ) + controls)

        if shownItems.isEmpty {
            lines.append(result.options.includeAllArchitectures
                ? "  未找到匹配的软件"
                : "  未发现 Intel-only 匹配项"
            )
        } else {
            let nameWidth = min(max(shownItems.map(\.name.count).max() ?? 0, 14), 28)
            let archWidth = 16
            let categoryWidth = 14
            let sourceWidth = 12
            lines.append(listHeaderLine(
                nameWidth: nameWidth,
                archWidth: archWidth,
                categoryWidth: categoryWidth,
                sourceWidth: sourceWidth
            ))
            for (index, item) in shownItems.enumerated() {
                let absoluteIndex = safeStartIndex + index
                let marker = numbered ? "\(absoluteIndex + 1)." : (selectedIndex == absoluteIndex ? "▶" : " ")
                lines.append(listItemLine(
                    item,
                    marker: marker,
                    nameWidth: nameWidth,
                    archWidth: archWidth,
                    categoryWidth: categoryWidth,
                    sourceWidth: sourceWidth
                ))
            }
        }

        if visible.count > shownItems.count {
            let rangeStart = shownItems.isEmpty ? 0 : safeStartIndex + 1
            let rangeEnd = safeStartIndex + shownItems.count
            let actionHint = includeControls ? "继续按 ↑/↓ 翻页" : "使用 --limit 调整显示数量"
            lines.append("  显示 \(rangeStart)-\(rangeEnd) / \(visible.count)；\(actionHint)")
        }

        let visibleTotal = result.visibleTotalCount()
        if result.options.limit > 0, visibleTotal > visible.count {
            lines.append("  结果已按 --limit 截断：\(visible.count) / \(visibleTotal)")
        }

        for warning in result.warnings {
            lines.append("  提示: \(sanitize(warning))")
        }

        if !result.options.includeSystemApps {
            lines.append("  提示: 使用 --system 可包含 /System/Applications。")
        }

        if numbered {
            lines.append("  非交互模式：仅显示候选；请在交互终端中运行 /arch 查看详情。")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderDetail(
        _ item: AppArchitectureItem,
        terminalWidth: Int = 100
    ) -> String {
        let pathWidth = max(24, terminalWidth - 12)
        let executable = item.executablePath.map { truncate(sanitize($0), width: pathWidth) } ?? "-"
        let systemStatus = item.isSystemApp ? "是" : "否"
        let lines = [
            "架构详情  b 返回列表 · q/Esc 退出",
            "  名称: \(sanitize(item.name))",
            "  架构: \(architectureLabel(for: item))",
            "  类型: \(item.category.rawValue)",
            "  来源: \(sourceLabel(item.source, isSystemApp: item.isSystemApp))",
            "  系统应用: \(systemStatus)",
            "  可执行文件: \(executable)",
            "  路径: \(truncate(sanitize(item.displayPath), width: pathWidth))",
            "  处理建议: \(recommendation(for: item))",
            "  安全提示: 当前详情页只展示信息，不会执行升级或修改文件。",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    static func parseOptions(argument: String?) -> AppArchitectureScanOptions? {
        var options = AppArchitectureScanOptions()
        var filterParts: [String] = []
        let parts = (argument ?? "")
            .split(separator: " ")
            .map(String.init)

        var index = 0
        while index < parts.count {
            let part = parts[index]
            switch part {
            case "--all":
                options.includeAllArchitectures = true
            case "--system":
                options.includeSystemApps = true
            case "--apps-only":
                guard options.scope != .packagesOnly else { return nil }
                options.scope = .appsOnly
            case "--packages-only":
                guard options.scope != .appsOnly else { return nil }
                options.scope = .packagesOnly
            case "--limit":
                let nextIndex = index + 1
                guard nextIndex < parts.count,
                      let limit = Int(parts[nextIndex]),
                      limit > 0
                else { return nil }
                options.limit = limit
                index += 1
            default:
                if part.hasPrefix("--") {
                    return nil
                }
                filterParts.append(part)
            }
            index += 1
        }

        let filter = filterParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        options.filter = filter.isEmpty ? nil : filter
        return options
    }

    static func helpText() -> String {
        """
        /arch [filter] [--all] [--system] [--apps-only|--packages-only] [--limit N]

          扫描本机 App、Homebrew、MacPorts 可执行文件架构，默认只显示 Intel-only 风险项。

          /arch
          /arch chrome
          /arch --all
          /arch --packages-only --all
          /arch --system --limit 120
        """
    }

    static func sanitize(_ raw: String) -> String {
        AppListFormatter.sanitize(raw)
    }

    private static func summaryLine(_ result: AppArchitectureScanResult) -> String {
        let filter = result.options.filter.map { " · 过滤: \($0)" } ?? ""
        let scope: String
        switch result.options.scope {
        case .all: scope = "Apps + Packages"
        case .appsOnly: scope = "Apps"
        case .packagesOnly: scope = "Packages"
        }
        return "架构扫描（\(scope)，共 \(result.totalCount) 个\(filter)）：Intel-only \(result.intelCount) · Universal \(result.universalCount) · Apple Silicon \(result.appleSiliconCount) · Unknown \(result.unknownCount)"
    }

    private static func titleLine(
        result: AppArchitectureScanResult,
        shownCount: Int,
        maxItems: Int,
        startIndex: Int = 0
    ) -> String {
        let filter = result.options.filter.map { " · 过滤: \($0)" } ?? ""
        let scope: String
        switch result.options.scope {
        case .all: scope = "Apps + Packages"
        case .appsOnly: scope = "Apps"
        case .packagesOnly: scope = "Packages"
        }
        let pageSize = max(1, maxItems)
        let visibleTotal = result.visibleItems().count
        let shown = visibleTotal > pageSize && shownCount > 0
            ? "，显示 \(startIndex + 1)-\(startIndex + shownCount)"
            : ""
        let mode = result.options.includeAllArchitectures ? "全部架构" : "Intel-only"
        return "软件架构候选（\(scope)，\(mode)，\(visibleTotal) 个\(shown)）\(filter)"
    }

    private static func headerLine(
        nameWidth: Int,
        archWidth: Int,
        categoryWidth: Int,
        sourceWidth: Int
    ) -> String {
        "  \(pad("名称", width: nameWidth))  \(pad("架构", width: archWidth))  \(pad("类型", width: categoryWidth))  \(pad("来源", width: sourceWidth))  路径"
    }

    private static func listHeaderLine(
        nameWidth: Int,
        archWidth: Int,
        categoryWidth: Int,
        sourceWidth: Int
    ) -> String {
        "  \(pad("名称", width: nameWidth))  \(pad("架构", width: archWidth))  \(pad("类型", width: categoryWidth))  \(pad("来源", width: sourceWidth))"
    }

    private static func itemLine(
        _ item: AppArchitectureItem,
        nameWidth: Int,
        archWidth: Int,
        categoryWidth: Int,
        sourceWidth: Int,
        pathWidth: Int
    ) -> String {
        let name = pad(truncate(sanitize(item.name), width: nameWidth), width: nameWidth)
        let arch = pad(truncate(AppArchitectureScanService.architectureList(item.architectures), width: archWidth), width: archWidth)
        let category = pad(truncate(item.category.rawValue, width: categoryWidth), width: categoryWidth)
        let source = pad(sourceLabel(item.source, isSystemApp: item.isSystemApp), width: sourceWidth)
        let path = truncate(sanitize(item.displayPath), width: pathWidth)
        return "  \(name)  \(arch)  \(category)  \(source)  \(path)"
    }

    private static func listItemLine(
        _ item: AppArchitectureItem,
        marker: String,
        nameWidth: Int,
        archWidth: Int,
        categoryWidth: Int,
        sourceWidth: Int
    ) -> String {
        let name = pad(truncate(sanitize(item.name), width: nameWidth), width: nameWidth)
        let arch = pad(truncate(architectureLabel(for: item), width: archWidth), width: archWidth)
        let category = pad(truncate(item.category.rawValue, width: categoryWidth), width: categoryWidth)
        let source = pad(sourceLabel(item.source, isSystemApp: item.isSystemApp), width: sourceWidth)
        return "\(marker) \(name)  \(arch)  \(category)  \(source)"
    }

    private static func architectureLabel(for item: AppArchitectureItem) -> String {
        AppArchitectureScanService.architectureList(item.architectures)
    }

    private static func recommendation(for item: AppArchitectureItem) -> String {
        switch item.category {
        case .intel:
            switch item.source {
            case .homebrew:
                return "Intel-only；优先确认 Homebrew 是否有 arm64/universal 版本。"
            case .macPorts:
                return "Intel-only；优先确认 MacPorts 是否有 arm64/universal 版本。"
            case .application where item.isSystemApp:
                return "Intel-only；系统应用通常应通过 macOS 更新处理。"
            case .application:
                return "Intel-only；建议查看厂商是否提供 Apple Silicon 或 Universal 版本。"
            }
        case .universal:
            return "已包含 Intel 和 Apple Silicon 架构。"
        case .appleSilicon:
            return "已是 Apple Silicon 架构。"
        case .unknown:
            return "未能识别 Mach-O 架构；可能不是原生可执行文件或没有读取权限。"
        }
    }

    private static func sourceLabel(_ source: AppArchitectureSource, isSystemApp: Bool) -> String {
        if source == .application, isSystemApp {
            return "System Apps"
        }
        return source.rawValue
    }

    private static func pad(_ text: String, width: Int) -> String {
        text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private static func truncate(_ text: String, width: Int) -> String {
        guard text.count > width else { return text }
        guard width > 1 else { return String(text.prefix(width)) }
        return String(text.prefix(width - 1)) + "…"
    }

    private static func normalizedStartIndex(_ startIndex: Int, total: Int, pageSize: Int) -> Int {
        guard total > 0 else { return 0 }
        let lastStart = max(0, total - pageSize)
        return min(max(0, startIndex), lastStart)
    }
}
