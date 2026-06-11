
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

    /// 过滤命令+skill 列表 — 大小写不敏感前缀匹配 + 精确匹配优先。
    /// - Parameters:
    ///   - query: 用户输入（含前导 `/`，如 `"/re"`）
    ///   - context: 当前上下文（用于过滤不可用命令）
    ///   - skills: 可用 skill 列表（默认空，向后兼容）
    /// - Returns: 匹配的列表项（已排序）
    static func filter(
        query: String,
        context: SlashCommandContext = SlashCommandContext(isAgentBusy: false, isSideSession: false),
        skills: [SkillInfo] = []
    ) -> [SlashPopupItem] {
        let availableCommands = context.filter(SlashCommand.allCases)
        // AC7: agent 忙碌时 skill 不可用
        let availableSkills = context.isAgentBusy ? [] : skills

        let searchText = String(query.dropFirst())  // 去掉前导 "/"

        guard !searchText.isEmpty else {
            // 只有 "/" → 返回所有可用命令 + skill，混合按 displayName 排序
            let cmdItems = availableCommands.map { SlashPopupItem(kind: .command($0), matchRange: nil) }
            let skillItems = availableSkills.map { SlashPopupItem(kind: .skill($0), matchRange: nil) }
            return (cmdItems + skillItems).sorted { $0.kind.displayName < $1.kind.displayName }
        }

        let lowerQuery = searchText.lowercased()
        let lowerQuerySlash = "/" + lowerQuery
        var items: [SlashPopupItem] = []

        // 匹配命令
        for cmd in availableCommands {
            for name in cmd.allNames {
                guard name.lowercased().hasPrefix(lowerQuerySlash) else { continue }

                if name == cmd.rawValue {
                    // rawValue 匹配 — 计算 matchRange 用于高亮
                    let start = cmd.rawValue.index(cmd.rawValue.startIndex, offsetBy: 1)  // skip "/"
                    let end = cmd.rawValue.index(start, offsetBy: min(searchText.count, cmd.rawValue.count - 1))
                    let range: Range<String.Index>? = (end <= cmd.rawValue.endIndex) ? start..<end : nil
                    items.append(SlashPopupItem(kind: .command(cmd), matchRange: range))
                } else {
                    // 别名匹配 — matchRange 为 nil（别名不在 rawValue 中）
                    items.append(SlashPopupItem(kind: .command(cmd), matchRange: nil))
                }
                break  // 一个名称匹配即可，避免重复添加
            }
        }

        // 匹配 skill（AC2/AC4: 前缀匹配 name + aliases）
        for skill in availableSkills {
            let skillDisplayName = "/\(skill.name)"
            let allSkillNames = [skillDisplayName] + skill.aliases.map { "/\($0)" }

            for name in allSkillNames {
                guard name.lowercased().hasPrefix(lowerQuerySlash) else { continue }

                if name == skillDisplayName {
                    // name 匹配 — 计算 matchRange
                    let start = skillDisplayName.index(skillDisplayName.startIndex, offsetBy: 1)  // skip "/"
                    let end = skillDisplayName.index(start, offsetBy: min(searchText.count, skillDisplayName.count - 1))
                    let range: Range<String.Index>? = (end <= skillDisplayName.endIndex) ? start..<end : nil
                    items.append(SlashPopupItem(kind: .skill(skill), matchRange: range))
                } else {
                    // 别名匹配
                    items.append(SlashPopupItem(kind: .skill(skill), matchRange: nil))
                }
                break  // AC4: 只添加一次，不因多别名重复
            }
        }

        // 排序：精确匹配优先，然后按 displayName 字母序
        return items.sorted { a, b in
            let aExact = exactMatch(kind: a.kind, query: lowerQuerySlash)
            let bExact = exactMatch(kind: b.kind, query: lowerQuerySlash)
            if aExact != bExact { return aExact }
            return a.kind.displayName < b.kind.displayName
        }
    }

    /// 检查 kind 是否精确匹配查询
    private static func exactMatch(kind: SlashPopupItemKind, query: String) -> Bool {
        switch kind {
        case .command(let cmd):
            return cmd.allNames.contains { $0.lowercased() == query }
        case .skill(let info):
            let allNames = ["/\(info.name)"] + info.aliases.map { "/\($0)" }
            return allNames.contains { $0.lowercased() == query }
        }
    }

    // MARK: - Render (AC1/AC3/AC6/AC8/AC9)

    /// 渲染命令+skill 列表为 ANSI 终端输出（两列布局）。
    ///
    /// Claude Code 风格：左侧名称列 + 右侧描述列（最多 2 行，超出截断加 "..."）。
    /// 根据 `termWidth` 自动计算列宽和描述折行，确保行宽不超终端宽度。
    static func render(items: [SlashPopupItem], selectedIndex: Int, theme: ChatTheme, termWidth: Int = 80) -> String {
        guard !items.isEmpty else {
            return "  无匹配命令"
        }

        // 名称列宽度：displayName (ASCII) + optional " [skill]" tag
        let nameColWidth = items.map { item in
            let nameWidth = item.kind.displayName.count
            let tagWidth = isSkillKind(item.kind) ? 9 : 0  // " [skill]"
            return nameWidth + tagWidth
        }.max() ?? 0

        // 布局: marker(3) + numberField(4) + nameCol + gap(2) = descStartCol
        let descStartCol = 3 + 4 + nameColWidth + 2
        let descWidth = max(20, termWidth - descStartCol)

        var resultLines: [String] = []
        for (index, item) in items.enumerated() {
            let isSelected = index == selectedIndex
            let marker = isSelected ? " \(selectedMarker) " : "   "
            let numberField = "\(index + 1).".padding(toLength: 4, withPad: " ", startingAt: 0)

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
