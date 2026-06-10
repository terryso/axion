
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

    /// 渲染命令+skill 列表为 ANSI 终端输出。
    static func render(items: [SlashPopupItem], selectedIndex: Int, theme: ChatTheme) -> String {
        guard !items.isEmpty else {
            return "  无匹配命令"
        }

        // 计算最大名称宽度（用于对齐）
        let maxNameWidth = items.map(\.kind.displayName.count).max() ?? 0

        var lines: [String] = []
        for (index, item) in items.enumerated() {
            let isSelected = index == selectedIndex
            let marker = isSelected ? " \(selectedMarker) " : "   "
            let number = "\(index + 1)."

            let displayName = item.kind.displayName

            let namePart: String
            if let range = item.matchRange, theme.isTTY {
                // 高亮匹配部分 — 使用 cyan + bold (AC8)
                let before = String(displayName[displayName.startIndex..<range.lowerBound])
                let matched = String(displayName[range])
                let after = String(displayName[range.upperBound..<displayName.endIndex])
                let highlight = "\u{1B}[1;36m\(matched)\u{1B}[0m"
                namePart = before + highlight + after
            } else {
                namePart = displayName
            }

            // 右侧描述部分
            let descriptionPart: String
            switch item.kind {
            case .command(let cmd):
                descriptionPart = cmd.helpText
            case .skill(let info):
                // AC3: 描述截断超过 50 字符
                let desc = info.description.count > 50
                    ? String(info.description.prefix(50)) + "..."
                    : info.description
                descriptionPart = "[skill]  \(desc)"
            }

            let padding = String(repeating: " ", count: max(0, maxNameWidth - displayName.count))

            // 选中行用 dim 整行标记
            let line: String
            if isSelected && theme.isTTY {
                line = "\u{1B}[2m\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(namePart)\(padding)\u{1B}[0m  \(descriptionPart)"
            } else {
                line = "\(marker)\(number.padding(toLength: 4, withPad: " ", startingAt: 0))\(namePart)\(padding)  \(descriptionPart)"
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}
