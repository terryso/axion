
/// 文件搜索弹出层列表项 — AC2/AC3。
struct FileSearchPopupItem: Equatable {
    let path: String
    /// 匹配范围在 path 中的字符区间（用于高亮）
    let matchRange: Range<String.Index>?
}

/// 文件搜索弹出层 — 纯函数渲染 + 过滤逻辑。AC2/AC3。
///
/// 复用 `SlashPopup` 的渲染模式（marker + number + path + highlight）。
/// 所有方法返回 String，零 I/O。通过 `ChatTheme` 注入颜色。
struct FileSearchPopup {

    /// 选中标记符号（与 SlashPopup 一致）
    static let selectedMarker = "▶"

    // MARK: - Filter (AC2)

    /// 在已有搜索结果中进行前缀匹配过滤。
    /// - Parameters:
    ///   - query: 用户输入的过滤词
    ///   - results: FileSearcher 返回的完整结果
    /// - Returns: 过滤后的列表项（带高亮范围）
    static func filter(query: String, results: [String]) -> [FileSearchPopupItem] {
        guard !query.isEmpty else {
            return results.map { FileSearchPopupItem(path: $0, matchRange: nil) }
        }

        let lowerQuery = query.lowercased()
        return results.compactMap { path -> FileSearchPopupItem? in
            let lowerPath = path.lowercased()
            // 子串匹配验证
            guard lowerPath.contains(lowerQuery) else { return nil }
            // 使用 caseInsensitive 搜索在原字符串中找到匹配范围
            let matchRange = path.range(of: query, options: .caseInsensitive)
            return FileSearchPopupItem(path: path, matchRange: matchRange)
        }
    }

    // MARK: - Render (AC2)

    /// 渲染文件候选列表为编号列表输出。AC2/AC3。
    /// - Parameters:
    ///   - items: 过滤后的列表项
    ///   - selectedIndex: 当前选中项索引（-1 表示无选中）
    ///   - theme: 颜色主题
    ///   - totalMatches: 总匹配数（用于显示截断提示）
    /// - Returns: 渲染后的多行字符串
    static func render(
        items: [FileSearchPopupItem],
        selectedIndex: Int,
        theme: ChatTheme,
        totalMatches: Int = 0
    ) -> String {
        guard !items.isEmpty else {
            return "  无匹配文件"
        }

        var lines: [String] = []

        for (index, item) in items.enumerated() {
            let isSelected = index == selectedIndex
            let marker = isSelected ? " \(selectedMarker) " : "   "
            let number = "\(index + 1)."

            let pathPart: String
            if let range = item.matchRange, theme.isTTY {
                // 高亮匹配部分 — 使用 cyan + bold
                let path = item.path
                let before = String(path[path.startIndex..<range.lowerBound])
                let matched = String(path[range])
                let after = String(path[range.upperBound..<path.endIndex])
                let highlight = "\u{1B}[1;36m\(matched)\u{1B}[0m"
                pathPart = before + highlight + after
            } else {
                pathPart = item.path
            }

            let line: String
            if isSelected && theme.isTTY {
                line = "\u{1B}[2m\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(pathPart)\u{1B}[0m"
            } else {
                line = "\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(pathPart)"
            }

            lines.append(line)
        }

        // AC2: 超过 20 条时显示截断提示
        if totalMatches > items.count {
            lines.append("  (显示前 \(items.count) 条，共 \(totalMatches) 个匹配)")
        }

        return lines.joined(separator: "\n")
    }
}
