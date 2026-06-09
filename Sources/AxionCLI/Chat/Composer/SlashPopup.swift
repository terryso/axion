
/// Slash popup 列表项 — 匹配的命令 + 高亮范围。
struct SlashPopupItem: Equatable {
    let command: SlashCommand
    /// 匹配文本在 rawValue 中的字符范围（用于高亮）
    let matchRange: Range<String.Index>?
}

/// Slash 命令面板 — 纯函数渲染 + 过滤逻辑。
///
/// AC1/AC2/AC5/AC6/AC9: 命令列表渲染、筛选、高亮。
/// 所有方法返回 String，零 I/O。通过 `ChatTheme` 注入颜色。
struct SlashPopup {

    /// 选中标记符号
    static let selectedMarker = "▶"

    // MARK: - Filter (AC2/AC3)

    /// 过滤命令列表 — 大小写不敏感前缀匹配 + 精确匹配优先。
    /// 使用 `SlashCommand.allNames` 遍历所有名称（rawValue + aliases）。
    /// - Parameters:
    ///   - query: 用户输入（含前导 `/`，如 `"/re"`）
    ///   - context: 当前上下文（用于过滤不可用命令）
    /// - Returns: 匹配的列表项（已排序）
    static func filter(
        query: String,
        context: SlashCommandContext = SlashCommandContext(isAgentBusy: false, isSideSession: false)
    ) -> [SlashPopupItem] {
        let available = context.filter(SlashCommand.allCases)
        let searchText = String(query.dropFirst())  // 去掉前导 "/"

        guard !searchText.isEmpty else {
            // 只有 "/" → 返回所有可用命令
            return available.map { SlashPopupItem(command: $0, matchRange: nil) }
                             .sorted { $0.command.rawValue < $1.command.rawValue }
        }

        let lowerQuery = searchText.lowercased()
        let lowerQuerySlash = "/" + lowerQuery
        var items: [SlashPopupItem] = []

        for cmd in available {
            // 使用 allNames 检查所有名称（rawValue + aliases）的前缀匹配
            for name in cmd.allNames {
                guard name.lowercased().hasPrefix(lowerQuerySlash) else { continue }

                if name == cmd.rawValue {
                    // rawValue 匹配 — 计算 matchRange 用于高亮
                    let start = cmd.rawValue.index(cmd.rawValue.startIndex, offsetBy: 1)  // skip "/"
                    let end = cmd.rawValue.index(start, offsetBy: min(searchText.count, cmd.rawValue.count - 1))
                    let range: Range<String.Index>? = (end <= cmd.rawValue.endIndex) ? start..<end : nil
                    items.append(SlashPopupItem(command: cmd, matchRange: range))
                } else {
                    // 别名匹配 — matchRange 为 nil（别名不在 rawValue 中）
                    items.append(SlashPopupItem(command: cmd, matchRange: nil))
                }
                break  // 一个名称匹配即可，避免重复添加
            }
        }

        // 排序：精确匹配优先（rawValue 或别名），然后按 rawValue 字母序
        return items.sorted { a, b in
            let aExact = a.command.allNames.contains { $0.lowercased() == lowerQuerySlash }
            let bExact = b.command.allNames.contains { $0.lowercased() == lowerQuerySlash }
            if aExact != bExact { return aExact }
            return a.command.rawValue < b.command.rawValue
        }
    }

    // MARK: - Render (AC1/AC6/AC9)

    /// 渲染命令列表为 ANSI 终端输出。
    /// - Parameters:
    ///   - items: 过滤后的列表项
    ///   - selectedIndex: 当前选中项索引（-1 表示无选中）
    ///   - theme: 颜色主题
    /// - Returns: 渲染后的多行字符串（每行一个命令）
    static func render(items: [SlashPopupItem], selectedIndex: Int, theme: ChatTheme) -> String {
        guard !items.isEmpty else {
            return "  无匹配命令"
        }

        var lines: [String] = []
        for (index, item) in items.enumerated() {
            let isSelected = index == selectedIndex
            let marker = isSelected ? " \(selectedMarker) " : "   "
            let number = "\(index + 1)."

            let namePart: String
            if let range = item.matchRange, theme.isTTY {
                // 高亮匹配部分 — 使用 cyan + bold
                let cmd = item.command.rawValue
                let before = String(cmd[cmd.startIndex..<range.lowerBound])
                let matched = String(cmd[range])
                let after = String(cmd[range.upperBound..<cmd.endIndex])
                let highlight = theme.isTTY ? "\u{1B}[1;36m\(matched)\u{1B}[0m" : matched
                namePart = before + highlight + after
            } else {
                namePart = item.command.rawValue
            }

            // 选中行用 dim 整行标记
            let line: String
            if isSelected && theme.isTTY {
                line = "\u{1B}[2m\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(namePart)\u{1B}[0m  \(item.command.helpText)"
            } else {
                line = "\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(namePart)  \(item.command.helpText)"
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}
