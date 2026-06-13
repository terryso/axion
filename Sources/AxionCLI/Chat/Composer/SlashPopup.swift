
/// Skill 摘要 — 仅供 SlashPopup 过滤/渲染使用。
/// 轻量 struct，避免引入 SDK 的 Skill 类型（含闭包等重字段）。
struct SkillInfo: Equatable, Sendable {
    let name: String
    let description: String
    let aliases: [String]
}

/// Slash popup 列表项类型 — 命令或 skill。
enum SlashPopupItemKind: Equatable {
    case command(SlashCommand)
    case skill(SkillInfo)
}

extension SlashPopupItemKind {
    /// 显示名称（用于匹配和渲染）。
    /// `.command` → `command.rawValue`（如 `/help`）
    /// `.skill` → `"/\(skill.name)"`（如 `/screenshot-analyze`）
    var displayName: String {
        switch self {
        case .command(let cmd): return cmd.rawValue
        case .skill(let info):  return "/\(info.name)"
        }
    }

    /// 是否接受参数（command 走 acceptsArgs，skill 始终接受参数）。
    var acceptsArgs: Bool {
        switch self {
        case .command(let cmd): return cmd.acceptsArgs
        case .skill:            return true  // skill 始终接受参数
        }
    }
}

/// Slash popup 列表项 — 匹配的命令/skill + 高亮范围。
struct SlashPopupItem: Equatable {
    let kind: SlashPopupItemKind
    /// 匹配文本在 displayName 中的字符范围（用于高亮）
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

    /// 过滤命令+skill 列表 — 大小写不敏感模糊匹配 + 最近使用优先。
    /// - Parameters:
    ///   - query: 用户输入（含前导 `/`，如 `"/re"`）
    ///   - context: 当前上下文（用于过滤不可用命令）
    ///   - skills: 可用 skill 列表（默认空，向后兼容）
    ///   - recentUsageCounts: 最近 slash token 使用次数，key 为小写命令/skill 名（含 `/`）
    /// - Returns: 匹配的列表项（已排序）
    static func filter(
        query: String,
        context: SlashCommandContext = SlashCommandContext(isAgentBusy: false, isSideSession: false),
        skills: [SkillInfo] = [],
        recentUsageCounts: [String: Int] = [:]
    ) -> [SlashPopupItem] {
        let availableCommands = context.filter(SlashCommand.allCases)
        // AC7: agent 忙碌时 skill 不可用
        let availableSkills = context.isAgentBusy ? [] : skills

        let searchText = String(query.dropFirst())  // 去掉前导 "/"

        guard !searchText.isEmpty else {
            // 只有 "/" → 返回所有可用命令 + skill，按最近 7 天使用次数排序
            let cmdItems = availableCommands.map { SlashPopupItem(kind: .command($0), matchRange: nil) }
            let skillItems = availableSkills.map { SlashPopupItem(kind: .skill($0), matchRange: nil) }
            return (cmdItems + skillItems).sorted {
                compareEmptyQuery($0, $1, recentUsageCounts: recentUsageCounts)
            }
        }

        var scoredItems: [(item: SlashPopupItem, score: Int)] = []

        // 匹配命令
        for cmd in availableCommands {
            if let match = bestMatch(
                displayName: cmd.rawValue,
                aliases: cmd.aliases.map { "/\($0)" },
                searchText: searchText
            ) {
                scoredItems.append((
                    item: SlashPopupItem(kind: .command(cmd), matchRange: match.range),
                    score: match.score
                ))
            }
        }

        // 匹配 skill（AC2/AC4: 模糊匹配 name + aliases）
        for skill in availableSkills {
            let skillDisplayName = "/\(skill.name)"
            if let match = bestMatch(
                displayName: skillDisplayName,
                aliases: skill.aliases.map { "/\($0)" },
                searchText: searchText
            ) {
                scoredItems.append((
                    item: SlashPopupItem(kind: .skill(skill), matchRange: match.range),
                    score: match.score
                ))
            }
        }

        return scoredItems.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let aUsage = recentUsageCount(for: a.item.kind, counts: recentUsageCounts)
            let bUsage = recentUsageCount(for: b.item.kind, counts: recentUsageCounts)
            if aUsage != bUsage { return aUsage > bUsage }
            let aPriority = kindPriority(a.item.kind)
            let bPriority = kindPriority(b.item.kind)
            if aPriority != bPriority { return aPriority < bPriority }
            return a.item.kind.displayName < b.item.kind.displayName
        }.map(\.item)
    }

    private struct MatchResult {
        let score: Int
        let range: Range<String.Index>?
    }

    private static func bestMatch(
        displayName: String,
        aliases: [String],
        searchText: String
    ) -> MatchResult? {
        var best: MatchResult?
        let candidates = [(displayName, true)] + aliases.map { ($0, false) }

        for (name, canHighlight) in candidates {
            guard let match = fuzzyMatch(
                name: name,
                searchText: searchText,
                highlightIn: canHighlight ? displayName : nil
            ) else { continue }

            if best == nil
                || match.score > best!.score
                || (match.score == best!.score && best!.range == nil && match.range != nil) {
                best = match
            }
        }

        return best
    }

    private static func fuzzyMatch(
        name: String,
        searchText: String,
        highlightIn displayName: String?
    ) -> MatchResult? {
        let target = name.hasPrefix("/") ? String(name.dropFirst()) : name
        let normalizedTarget = target.lowercased()
        let normalizedSearch = searchText.lowercased()

        guard !normalizedSearch.isEmpty else {
            return MatchResult(score: 0, range: nil)
        }

        if normalizedTarget == normalizedSearch {
            return MatchResult(
                score: 400,
                range: displayName.map { displayRange(in: $0, startOffset: 1, length: searchText.count) }
            )
        }

        if normalizedTarget.hasPrefix(normalizedSearch) {
            return MatchResult(
                score: 300,
                range: displayName.map { displayRange(in: $0, startOffset: 1, length: searchText.count) }
            )
        }

        if let range = normalizedTarget.range(of: normalizedSearch) {
            let startOffset = normalizedTarget.distance(from: normalizedTarget.startIndex, to: range.lowerBound) + 1
            return MatchResult(
                score: 200,
                range: displayName.map { displayRange(in: $0, startOffset: startOffset, length: searchText.count) }
            )
        }

        if let offsets = subsequenceOffsets(query: normalizedSearch, in: normalizedTarget) {
            let length = offsets.end - offsets.start + 1
            return MatchResult(
                score: 100,
                range: displayName.map { displayRange(in: $0, startOffset: offsets.start + 1, length: length) }
            )
        }

        return nil
    }

    private static func subsequenceOffsets(query: String, in target: String) -> (start: Int, end: Int)? {
        var queryIndex = query.startIndex
        var firstOffset: Int?
        var lastOffset: Int?

        for (offset, char) in target.enumerated() {
            guard queryIndex < query.endIndex, char == query[queryIndex] else {
                continue
            }
            if firstOffset == nil { firstOffset = offset }
            lastOffset = offset
            queryIndex = query.index(after: queryIndex)
            if queryIndex == query.endIndex {
                break
            }
        }

        guard queryIndex == query.endIndex,
              let firstOffset,
              let lastOffset
        else { return nil }
        return (firstOffset, lastOffset)
    }

    private static func displayRange(in displayName: String, startOffset: Int, length: Int) -> Range<String.Index> {
        let lower = displayName.index(displayName.startIndex, offsetBy: min(startOffset, displayName.count))
        let upperOffset = min(startOffset + length, displayName.count)
        let upper = displayName.index(displayName.startIndex, offsetBy: upperOffset)
        return lower..<upper
    }

    private static func compareEmptyQuery(
        _ a: SlashPopupItem,
        _ b: SlashPopupItem,
        recentUsageCounts: [String: Int]
    ) -> Bool {
        let aUsage = recentUsageCount(for: a.kind, counts: recentUsageCounts)
        let bUsage = recentUsageCount(for: b.kind, counts: recentUsageCounts)
        if aUsage != bUsage { return aUsage > bUsage }
        let aPriority = kindPriority(a.kind)
        let bPriority = kindPriority(b.kind)
        if aPriority != bPriority { return aPriority < bPriority }
        return a.kind.displayName < b.kind.displayName
    }

    private static func recentUsageCount(for kind: SlashPopupItemKind, counts: [String: Int]) -> Int {
        usageNames(for: kind).reduce(0) { total, name in
            total + (counts[name.lowercased()] ?? 0)
        }
    }

    private static func usageNames(for kind: SlashPopupItemKind) -> [String] {
        switch kind {
        case .command(let cmd):
            return cmd.allNames
        case .skill(let info):
            return ["/\(info.name)"] + info.aliases.map { "/\($0)" }
        }
    }

    private static func kindPriority(_ kind: SlashPopupItemKind) -> Int {
        switch kind {
        case .command: return 0
        case .skill: return 1
        }
    }

    // MARK: - Render (AC1/AC3/AC6/AC8/AC9)

    /// 渲染命令+skill 列表为 ANSI 终端输出（两列布局）。
    ///
    /// Claude Code 风格：左侧名称列 + 右侧描述列（最多 2 行，超出截断加 "..."）。
    /// 根据 `termWidth` 自动计算列宽和描述折行，确保行宽不超终端宽度。
    static func render(
        items: [SlashPopupItem],
        selectedIndex: Int,
        theme: ChatTheme,
        termWidth: Int = 80,
        maxItems: Int? = nil,
        startIndex: Int = 0
    ) -> String {
        guard !items.isEmpty else {
            return "  无匹配命令"
        }

        let pageSize = max(1, maxItems ?? items.count)
        let safeStartIndex = normalizedStartIndex(startIndex, total: items.count, pageSize: pageSize)
        let shownItems = Array(items.dropFirst(safeStartIndex).prefix(pageSize))

        // 名称列宽度：displayName (ASCII) + optional " [skill]" tag
        let nameColWidth = shownItems.map { item in
            let nameWidth = item.kind.displayName.count
            let tagWidth = isSkillKind(item.kind) ? 9 : 0  // " [skill]"
            return nameWidth + tagWidth
        }.max() ?? 0

        // 布局: marker(3) + numberField(4) + nameCol + gap(2) = descStartCol
        let descStartCol = 3 + 4 + nameColWidth + 2
        let descWidth = max(20, termWidth - descStartCol)

        var resultLines: [String] = []
        for (index, item) in shownItems.enumerated() {
            let absoluteIndex = safeStartIndex + index
            let isSelected = absoluteIndex == selectedIndex
            let marker = isSelected ? " \(selectedMarker) " : "   "
            let numberField = "\(absoluteIndex + 1).".padding(toLength: 4, withPad: " ", startingAt: 0)

            // 名称（含匹配高亮）
            let displayName = item.kind.displayName
            let namePart = buildNamePart(displayName, matchRange: item.matchRange, theme: theme)

            // [skill] 标签
            let tag = isSkillKind(item.kind) ? " [skill]" : ""

            // 描述文本
            let description: String
            switch item.kind {
            case .command(let cmd): description = cmd.helpText
            case .skill(let info): description = info.description
            }

            // 描述折行：最多 2 行，超出截断加 "..."
            let descLines = wrapDescription(description, maxWidth: descWidth, maxLines: 2)

            // 名称列右侧 padding
            let nameVisibleWidth = displayName.count + (isSkillKind(item.kind) ? 9 : 0)
            let namePadding = String(repeating: " ", count: max(0, nameColWidth - nameVisibleWidth))

            // 第一行: marker + number + name + tag + padding + gap + descLine0
            let linePrefix = "\(marker)\(numberField)"
            let firstLine: String
            if isSelected && theme.isTTY {
                firstLine = "\u{1B}[2m\(linePrefix)\u{1B}[0m\(namePart)\u{1B}[2m\(tag)\(namePadding)\u{1B}[0m  \(descLines[0])"
            } else {
                firstLine = "\(linePrefix)\(namePart)\(tag)\(namePadding)  \(descLines[0])"
            }
            resultLines.append(firstLine)

            // 描述续行（缩进对齐到描述列）
            for i in 1..<descLines.count {
                let contIndent = String(repeating: " ", count: descStartCol)
                resultLines.append("\(contIndent)\(descLines[i])")
            }
        }

        return resultLines.joined(separator: "\n")
    }

    // MARK: - Private: Name Helpers

    private static func isSkillKind(_ kind: SlashPopupItemKind) -> Bool {
        if case .skill = kind { return true }
        return false
    }

    private static func normalizedStartIndex(_ startIndex: Int, total: Int, pageSize: Int) -> Int {
        guard total > 0 else { return 0 }
        let lastStart = max(0, total - pageSize)
        return min(max(0, startIndex), lastStart)
    }

    private static func buildNamePart(
        _ displayName: String,
        matchRange: Range<String.Index>?,
        theme: ChatTheme
    ) -> String {
        guard let range = matchRange, theme.isTTY else {
            return displayName
        }
        let before = String(displayName[displayName.startIndex..<range.lowerBound])
        let matched = String(displayName[range])
        let after = String(displayName[range.upperBound..<displayName.endIndex])
        let highlight = "\u{1B}[1;36m\(matched)\u{1B}[0m"
        return before + highlight + after
    }

    // MARK: - Private: Description Wrapping

    /// 将描述文本按显示宽度折行，最多 `maxLines` 行，超出部分用 "..." 截断。
    ///
    /// 正确处理 CJK 宽字符：每个 CJK 字符占 2 列。
    /// 按字符边界折行（CJK 天然按字符断词，英文可能在单词中间断开）。
    private static func wrapDescription(_ text: String, maxWidth: Int, maxLines: Int = 2) -> [String] {
        guard !text.isEmpty else { return [""] }
        guard maxWidth > 3 else { return ["..."] }

        let ellipsis = "..."
        var lines: [String] = []
        var idx = text.startIndex

        while idx < text.endIndex && lines.count < maxLines {
            let isLastLine = lines.count == maxLines - 1
            let effectiveMax = isLastLine ? maxWidth - 3 : maxWidth

            let lineStart = idx
            var width = 0

            while idx < text.endIndex {
                let char = text[idx]
                let cw = charDisplayWidth(char)
                if width + cw > effectiveMax { break }
                width += cw
                idx = text.index(after: idx)
            }

            let hasMore = idx < text.endIndex
            let line = String(text[lineStart..<idx])

            if isLastLine && hasMore {
                lines.append(line + ellipsis)
            } else {
                lines.append(line)
            }
        }

        return lines.isEmpty ? [""] : lines
    }

    /// 计算单个字符的显示宽度。
    /// CJK/wide → 2 列，default-ignorable → 0 列，其他 → 1 列。
    private static func charDisplayWidth(_ char: Character) -> Int {
        for scalar in char.unicodeScalars {
            if scalar.properties.isDefaultIgnorableCodePoint { return 0 }
            return isWideUnicodeScalar(scalar) ? 2 : 1
        }
        return 1
    }

    /// 判断 Unicode scalar 是否为宽字符（CJK/全角等）。
    private static func isWideUnicodeScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // CJK Unified Ideographs
        if v >= 0x4E00 && v <= 0x9FFF { return true }
        // CJK Extension A
        if v >= 0x3400 && v <= 0x4DBF { return true }
        // CJK Compatibility Ideographs
        if v >= 0xF900 && v <= 0xFAFF { return true }
        // CJK Radicals / Kangxi
        if v >= 0x2E80 && v <= 0x2FDF { return true }
        // CJK Symbols, Hiragana, Katakana
        if v >= 0x3000 && v <= 0x33FF { return true }
        // Hangul Syllables
        if v >= 0xAC00 && v <= 0xD7AF { return true }
        // Fullwidth Forms
        if v >= 0xFF01 && v <= 0xFF60 { return true }
        // CJK Compatibility Forms
        if v >= 0xFE30 && v <= 0xFE4F { return true }
        return false
    }
}
