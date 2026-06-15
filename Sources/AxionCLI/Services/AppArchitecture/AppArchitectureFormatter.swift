import Foundation

struct AppArchitectureFormatter {
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

    private static func headerLine(
        nameWidth: Int,
        archWidth: Int,
        categoryWidth: Int,
        sourceWidth: Int
    ) -> String {
        "  \(pad("名称", width: nameWidth))  \(pad("架构", width: archWidth))  \(pad("类型", width: categoryWidth))  \(pad("来源", width: sourceWidth))  路径"
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
}
