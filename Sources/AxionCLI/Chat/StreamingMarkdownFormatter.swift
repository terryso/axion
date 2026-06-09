import Foundation

/// 流式 Markdown 内联格式化器 — Codex 启发，增强 LLM 流式输出中非代码文本的可读性。
///
/// 处理的 Markdown 元素：
/// - 标题（`#` ~ `####`）→ 粗体 + 颜色 + H1/H2 下划线装饰
/// - 粗体（`**text**`）→ 明亮/粗体 ANSI
/// - 斜体（`*text*`、`_text_`）→ italic ANSI
/// - 删除线（`~~text~~`）→ ANSI strikethrough + dim 颜色
/// - 内联代码（`` `code` ``）→ 独立颜色高亮
/// - 内联链接（`[text](url)`）→ 颜色文本 + OSC 8 可点击超链接
/// - 图片（`![alt](url)`）→ `[📷 alt]` 颜色占位
/// - 水平分割线（`---`、`***`、`___`）→ Unicode 可视化分隔线
/// - 有序列表（`1. text`）→ 彩色编号 + 缩进
/// - 无序列表（`- text`、`* text`、`+ text`）→ 彩色符号 + 缩进
/// - 任务列表（`- [ ]`、`- [x]`）→ Unicode 复选框 + 缩进
/// - 引用块（`> text`）→ dim 前缀竖线
///
/// 设计原则：
/// - 纯函数，无状态，无 I/O（由调用方控制输出）
/// - 只处理完整行（行级格式化，不跨行）
/// - 支持所有 TerminalColorProfile 降级
/// - 非 TTY 环境下原样输出
/// - 与 StreamingCodeBlockRenderer 互补：代码块边框内的内容不由本组件处理
struct StreamingMarkdownFormatter: Sendable {

    /// 终端颜色 profile
    private let profile: TerminalColorProfile

    /// 是否为 TTY 环境
    private let isTTY: Bool

    /// 终端宽度（用于分割线长度）
    private let terminalWidth: Int

    /// 超链接格式化器 — 用于渲染内联链接为 OSC 8 可点击超链接
    private let hyperlinkFormatter: TerminalHyperlinkFormatter?

    init(
        profile: TerminalColorProfile = TerminalColorProfile.detect(),
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        terminalWidth: Int = 80,
        hyperlinkFormatter: TerminalHyperlinkFormatter? = nil
    ) {
        self.profile = isTTY ? profile : .unknown
        self.isTTY = isTTY
        self.terminalWidth = terminalWidth
        self.hyperlinkFormatter = hyperlinkFormatter
    }

    // MARK: - Public API

    /// 格式化一行 Markdown 文本，返回带 ANSI 样式的字符串。
    ///
    /// 处理优先级（互斥，从高到低）：
    /// 1. 水平分割线（整行匹配 `---`/`***`/`___`）
    /// 2. 标题（`#` ~ `####` 开头）
    /// 3. 引用块（`> ` 开头）
    /// 4. 有序/无序列表（`1. ` / `- ` / `* ` / `+ ` 开头）
    /// 5. 内联元素（粗体 + 斜体 + 内联代码）
    ///
    /// - Parameter line: 不含末尾换行符的完整行
    /// - Returns: 格式化后的字符串
    func formatLine(_ line: String) -> String {
        guard isTTY && !line.isEmpty else { return line }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 1. 水平分割线
        if isHorizontalRule(trimmed) {
            return renderHorizontalRule()
        }

        // 2. 标题
        if let heading = parseHeading(trimmed) {
            return renderHeading(originalLine: line, level: heading.level, text: heading.text)
        }

        // 3. 引用块
        if let blockquote = parseBlockquote(line) {
            return renderBlockquote(prefix: blockquote.prefix, text: blockquote.text)
        }

        // 4. 任务列表（优先于普通列表，因为 `- [ ]` 以 `- ` 开头）
        if let task = parseTaskList(trimmed) {
            return renderTaskList(originalLine: line, checked: task.checked, text: task.text)
        }

        // 5. 列表项
        if let list = parseList(trimmed) {
            return renderList(originalLine: line, marker: list.marker, text: list.text)
        }

        // 6. 内联元素（粗体 + 斜体 + 删除线 + 内联代码 + 链接）
        return formatInlineElements(line)
    }

    // MARK: - Heading Detection

    /// 标题解析结果
    private struct HeadingInfo {
        let level: Int       // 1-4
        let text: String     // 去除 # 前缀的文本
    }

    /// 从行首检测 Markdown 标题级别和文本。
    /// 支持 `# ` ~ `#### ` 格式（`#` 后必须跟空格）。
    private func parseHeading(_ trimmed: String) -> HeadingInfo? {
        var hashCount = 0
        for char in trimmed {
            if char == "#" {
                hashCount += 1
            } else {
                break
            }
        }

        guard hashCount >= 1 && hashCount <= 4 else { return nil }

        // `#` 后必须跟空格（避免匹配 `##nope` 或 `##### too deep`）
        let afterHashes = trimmed.dropFirst(hashCount)
        guard afterHashes.first == " " else { return nil }

        let text = String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        return HeadingInfo(level: hashCount, text: text)
    }

    // MARK: - Horizontal Rule Detection

    /// 检测是否为水平分割线（`---`、`***`、`___` 至少 3 个字符）。
    private func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }

        let first = trimmed.first!
        guard first == "-" || first == "*" || first == "_" else { return false }

        // 全部为同一字符
        let allSame = trimmed.allSatisfy { $0 == first }
        guard allSame else { return false }

        return trimmed.count >= 3
    }

    // MARK: - Blockquote Detection

    /// 引用块解析结果
    private struct BlockquoteInfo {
        let prefix: String   // 原始 > 前缀（含前导空格）
        let text: String     // 引用内容
    }

    /// 检测引用块（`> text` 或 `>text`）。
    /// 保留前导空格缩进，提取引用内容。
    private func parseBlockquote(_ line: String) -> BlockquoteInfo? {
        // 找到第一个非空格字符
        let leadingSpaces = line.prefix(while: { $0 == " " })
        let afterSpaces = line.dropFirst(leadingSpaces.count)

        guard afterSpaces.first == ">" else { return nil }

        // > 后可选空格
        let afterGt = afterSpaces.dropFirst()
        let text: String
        if afterGt.first == " " {
            text = String(afterGt.dropFirst())
        } else {
            text = String(afterGt)
        }

        // 空引用行也有效（用于引用块内的空行）
        let prefix = String(leadingSpaces) + ">"
        return BlockquoteInfo(prefix: prefix, text: text)
    }

    // MARK: - List Detection

    /// 列表项解析结果
    private struct ListInfo {
        let marker: String   // 原始标记（如 `-`、`1.`、`*`）
        let text: String     // 列表项内容
    }

    /// 检测有序或无序列表项。
    ///
    /// 无序：`- text`、`* text`、`+ text`（标记后必须跟空格）
    /// 有序：`1. text`、`12) text`（数字 + `.` 或 `)` + 空格）
    private func parseList(_ trimmed: String) -> ListInfo? {
        // 无序列表：- / * / + 后跟空格
        let unorderedMarkers = ["- ", "* ", "+ "]
        for marker in unorderedMarkers {
            if trimmed.hasPrefix(marker) {
                let markerChar = String(marker.dropLast())  // 去掉尾部空格
                let text = String(trimmed.dropFirst(marker.count))
                guard !text.isEmpty else { return nil }
                // 排除任务列表模式（- [ ] / - [x]）
                if markerChar == "-" && (text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text == "[ ]" || text == "[x]") {
                    return nil
                }
                return ListInfo(marker: markerChar, text: text)
            }
        }

        // 有序列表：数字 + . 或 ) + 空格
        let chars = Array(trimmed)
        var digitEnd = 0
        while digitEnd < chars.count && chars[digitEnd].isNumber {
            digitEnd += 1
        }
        guard digitEnd > 0 && digitEnd < chars.count - 1 else { return nil }

        let delimiter = chars[digitEnd]
        guard delimiter == "." || delimiter == ")" else { return nil }

        // 分隔符后必须跟空格
        guard digitEnd + 1 < chars.count && chars[digitEnd + 1] == " " else { return nil }

        let marker = String(chars[0...digitEnd])  // e.g. "1." or "12)"
        let text = String(trimmed.dropFirst(digitEnd + 2))
        guard !text.isEmpty else { return nil }

        return ListInfo(marker: marker, text: text)
    }

    // MARK: - Task List Detection

    /// 任务列表解析结果
    private struct TaskListInfo {
        let checked: Bool    // true = [x], false = [ ]
        let text: String     // 任务描述
    }

    /// 检测任务列表项（`- [ ]` 或 `- [x]`）。
    ///
    /// 支持 `- [ ] text`、`- [x] text`、`* [ ] text`、`+ [x] text` 格式。
    /// 方括号内的空格必须是精确的 ` ` 或 `x`/`X`。
    private func parseTaskList(_ trimmed: String) -> TaskListInfo? {
        let markers = ["- ", "* ", "+ "]
        for marker in markers {
            if trimmed.hasPrefix(marker) {
                let afterMarker = String(trimmed.dropFirst(marker.count))
                // 检查 [ ] 或 [x] / [X]
                guard afterMarker.hasPrefix("[") else { continue }
                let chars = Array(afterMarker)
                guard chars.count >= 3 else { continue }
                guard chars[2] == "]" else { continue }

                let checked: Bool
                switch chars[1] {
                case " ":
                    checked = false
                case "x", "X":
                    checked = true
                default:
                    continue
                }

                // 方括号后必须跟空格或为行尾
                let textStart: String.Index
                if chars.count > 3 && chars[3] == " " {
                    textStart = afterMarker.index(afterMarker.startIndex, offsetBy: 4)
                } else if chars.count == 3 {
                    // `- [ ]` 无后续文本 — 空任务
                    return TaskListInfo(checked: checked, text: "")
                } else {
                    continue
                }

                let text = String(afterMarker[textStart...])
                return TaskListInfo(checked: checked, text: text)
            }
        }
        return nil
    }

    // MARK: - Rendering

    /// 渲染水平分割线 — dim 色 Unicode 线
    private func renderHorizontalRule() -> String {
        let (dimCode, resetCode) = dimCodes()
        let line = String(repeating: "─", count: terminalWidth)
        return "\(dimCode)\(line)\(resetCode)"
    }

    /// 渲染标题 — 粗体 + 级别相关颜色 + H1/H2 下划线装饰。
    ///
    /// H1: `# Title` + `═══════`（双线下划线，长度与标题文本对齐）
    /// H2: `## Title` + `───────`（单线下划线）
    /// H3/H4: 仅颜色 + 粗体（无下划线）
    private func renderHeading(originalLine: String, level: Int, text: String) -> String {
        let (boldCode, resetCode) = boldCodes()
        let colorCode = headingColor(level: level)

        // 保留原始行的前导空格缩进
        let leadingSpaces = originalLine.prefix(while: { $0 == " " })
        let hashPrefix = String(repeating: "#", count: level)

        // 格式化文本（处理内联元素）
        let formattedText = formatInlineElements(text)

        let headingLine = "\(leadingSpaces)\(colorCode)\(boldCode)\(hashPrefix)\(resetCode) \(formattedText)"

        // H1/H2 下划线装饰 — 使用标题文本的可见长度计算下划线宽度
        if level <= 2 {
            let (dimCode, dimReset) = dimCodes()
            let underlineChar = level == 1 ? "═" : "─"
            // 计算可见字符宽度：# 前缀(1-2字符) + 空格(1) + 文本长度
            let prefixWidth = hashPrefix.count + 1  // "# " or "## "
            let textWidth = text.count
            let underlineWidth = prefixWidth + textWidth
            let underline = String(repeating: underlineChar, count: underlineWidth)
            return "\(headingLine)\n\(dimCode)\(underline)\(dimReset)"
        }

        return headingLine
    }

    /// 渲染引用块 — dim 竖线前缀 + 引用内容。
    ///
    /// TTY 示例：`  │ Quoted text here`
    /// 非 TTY：原样输出
    private func renderBlockquote(prefix: String, text: String) -> String {
        let (dimCode, resetCode) = dimCodes()
        // 将原始 > 替换为 Unicode 竖线
        let visualPrefix = prefix.replacingOccurrences(of: ">", with: "│")
        // 分离前导空格和竖线标记
        let leadingSpaces = String(visualPrefix.prefix(while: { $0 == " " }))
        let pipePart = String(visualPrefix.dropFirst(leadingSpaces.count))
        let formattedText = formatInlineElements(text)
        return "\(leadingSpaces)\(dimCode)\(pipePart)\(resetCode) \(formattedText)"
    }

    /// 渲染列表项 — 彩色标记 + 内容。
    ///
    /// 无序 TTY 示例：`  • List item text`
    /// 有序 TTY 示例：`  1. List item text`（编号着色）
    private func renderList(originalLine: String, marker: String, text: String) -> String {
        let (markerColor, resetCode) = listMarkerCodes()

        // 计算原始行的前导空格
        let leadingSpaces = originalLine.prefix(while: { $0 == " " })

        // 判断是否为有序列表
        let isOrdered = marker.first?.isNumber == true

        if isOrdered {
            // 有序列表：保留编号，着色
            let formattedText = formatInlineElements(text)
            return "\(leadingSpaces)\(markerColor)\(marker)\(resetCode) \(formattedText)"
        } else {
            // 无序列表：替换标记为 Unicode bullet
            let bullet = "•"
            let formattedText = formatInlineElements(text)
            return "\(leadingSpaces)\(markerColor)\(bullet)\(resetCode) \(formattedText)"
        }
    }

    /// 渲染任务列表项 — Unicode 复选框 + 描述文本。
    ///
    /// TTY 示例：`  ☑ Task completed`（绿色勾选）
    /// TTY 示例：`  ☐ Task pending`（dim 未勾选）
    private func renderTaskList(originalLine: String, checked: Bool, text: String) -> String {
        let (markerColor, resetCode) = taskListMarkerCodes(checked: checked)

        let leadingSpaces = originalLine.prefix(while: { $0 == " " })
        let checkbox = checked ? "☑" : "☐"
        let formattedText = text.isEmpty ? "" : " \(formatInlineElements(text))"

        return "\(leadingSpaces)\(markerColor)\(checkbox)\(resetCode)\(formattedText)"
    }

    /// 标题颜色 — 级别越深颜色越暗
    private func headingColor(level: Int) -> String {
        switch profile {
        case .trueColor:
            switch level {
            case 1: return "\u{1B}[38;2;129;140;248m"  // 紫蓝（与 KeyHintsFormatter 一致）
            case 2: return "\u{1B}[38;2;96;165;250m"   // 天蓝
            case 3: return "\u{1B}[38;2;148;163;184m"  // 灰蓝
            default: return "\u{1B}[38;2;148;163;184m" // 灰蓝
            }
        case .ansi256:
            switch level {
            case 1: return "\u{1B}[38;5;104m"
            case 2: return "\u{1B}[38;5;111m"
            case 3: return "\u{1B}[38;5;246m"
            default: return "\u{1B}[38;5;246m"
            }
        case .ansi16:
            return "\u{1B}[36m"  // cyan
        case .unknown:
            return ""
        }
    }

    // MARK: - Inline Element Formatting

    /// 格式化行内 Markdown 元素（粗体 + 斜体 + 删除线 + 内联代码 + 链接 + 图片）。
    ///
    /// 扫描策略：逐字符扫描，维护粗体/斜体/代码/删除线开关状态。
    /// - `**text**` → 粗体开关（ANSI bold）
    /// - `*text*` → 斜体开关（ANSI italic）
    /// - `_text_` → 斜体开关（ANSI italic）
    /// - `~~text~~` → 删除线开关（ANSI strikethrough + dim 颜色）
    /// - `` `code` `` → 内联代码开关（ANSI 颜色）
    /// - `![alt](url)` → `[📷 alt]` 颜色图片占位
    /// - `[text](url)` → 颜色文本 + OSC 8 超链接
    ///
    /// 注意：`*` 优先匹配 `**`（粗体），单 `*` 在非粗体上下文中视为斜体。
    /// 检测顺序：`~~` → `**` → `` ` `` → `![`（图片）→ `[`（链接）→ `*` → `_`。
    private func formatInlineElements(_ line: String) -> String {
        guard isTTY && profile != .unknown else { return line }

        // 快速路径：不含任何格式标记的行直接返回
        let needsFormatting = line.contains("**") || line.contains("`")
            || line.contains("*") || line.contains("_")
            || line.contains("~~") || line.contains("](")
            || line.contains("![")
        guard needsFormatting else { return line }

        var result = ""
        let chars = Array(line)
        var i = 0
        var inBold = false
        var inItalic = false
        var inCode = false
        var inStrikethrough = false

        let (boldOn, boldOff) = boldToggleCodes()
        let (italicOn, italicOff) = italicToggleCodes()
        let (codeOn, codeOff) = inlineCodeToggleCodes()
        let (strikeOn, strikeOff) = strikethroughToggleCodes()

        while i < chars.count {
            // 检测 `~~` 删除线标记（优先于其他标记，避免 ~~ 中的 ~ 干扰）
            if i + 1 < chars.count && chars[i] == "~" && chars[i + 1] == "~" && !inCode && !inBold {
                if inStrikethrough {
                    result += strikeOff
                    inStrikethrough = false
                } else {
                    // 关闭斜体再进入删除线（防止样式冲突）
                    if inItalic {
                        result += italicOff
                        inItalic = false
                    }
                    result += strikeOn
                    inStrikethrough = true
                }
                i += 2
                continue
            }

            // 检测 `**` 粗体标记（优先级最高，避免误匹配为斜体）
            if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "*" && !inCode && !inStrikethrough {
                if inBold {
                    result += boldOff
                    inBold = false
                } else {
                    result += boldOn
                    inBold = true
                }
                i += 2
                continue
            }

            // 检测 `` ` `` 内联代码标记（优先于斜体，避免代码内的 * 被误处理）
            if chars[i] == "`" && !inBold && !inStrikethrough {
                if inCode {
                    result += codeOff
                    inCode = false
                } else {
                    // 关闭斜体再进入代码（防止样式冲突）
                    if inItalic {
                        result += italicOff
                        inItalic = false
                    }
                    result += codeOn
                    inCode = true
                }
                i += 1
                continue
            }

            // 检测 `![alt](url)` 图片语法（非粗体/非代码/非删除线上下文）
            // 必须在 `[` 链接检测之前，因为 `![` 是 `[` 的前缀
            if chars[i] == "!" && i + 1 < chars.count && chars[i + 1] == "[" && !inBold && !inCode && !inStrikethrough {
                if let imageResult = parseAndRenderImage(chars: chars, startIndex: i) {
                    result += imageResult.rendered
                    i = imageResult.endIndex
                    continue
                }
            }

            // 检测 `[text](url)` 内联链接（非粗体/非代码/非删除线上下文）
            if chars[i] == "[" && !inBold && !inCode && !inStrikethrough {
                if let linkResult = parseAndRenderInlineLink(chars: chars, startIndex: i) {
                    result += linkResult.rendered
                    i = linkResult.endIndex
                    continue
                }
            }

            // 检测 `*` 斜体标记（仅在非粗体、非代码、非删除线上下文）
            if chars[i] == "*" && !inBold && !inCode && !inStrikethrough {
                // 启发式：`*` 应该是 Markdown 斜体标记而非数学/符号乘号
                let prevChar: Character? = i > 0 ? chars[i - 1] : nil
                let nextChar: Character? = i + 1 < chars.count ? chars[i + 1] : nil

                // 运算符/符号邻居时跳过（如 --*, 3*4, x*y）
                let operatorChars: Set<Character> = ["-", "+", "=", "/", "\\", "|", "&", "^", "%", "~", "<", ">"]
                let prevIsOperator = prevChar.map { operatorChars.contains($0) } ?? false
                let nextIsOperator = nextChar.map { operatorChars.contains($0) } ?? false

                if prevIsOperator || nextIsOperator {
                    result += String(chars[i])
                    i += 1
                    continue
                }

                if inItalic {
                    result += italicOff
                    inItalic = false
                } else {
                    result += italicOn
                    inItalic = true
                }
                i += 1
                continue
            }

            // 检测 `_` 斜体标记（仅在非粗体、非代码上下文，且前后为单词边界）
            if chars[i] == "_" && !inBold && !inCode && !inStrikethrough {
                // 简单启发式：前后不能是字母/数字（避免误匹配 snake_case 变量名）
                let prevIsAlnum = i > 0 && chars[i - 1].isLetter || (i > 0 && chars[i - 1].isNumber)
                let nextIsAlnum = i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1].isNumber)

                // 如果前后都是字母/数字，这是 snake_case 标识符，跳过
                if prevIsAlnum && nextIsAlnum {
                    result += String(chars[i])
                    i += 1
                    continue
                }

                if inItalic {
                    result += italicOff
                    inItalic = false
                } else {
                    result += italicOn
                    inItalic = true
                }
                i += 1
                continue
            }

            result += String(chars[i])
            i += 1
        }

        // 如果有未关闭的样式，追加 reset
        if inBold || inItalic || inCode || inStrikethrough {
            result += "\u{1B}[0m"
        }

        return result
    }

    // MARK: - Inline Link Parsing & Rendering

    /// 内联链接解析结果（内部使用）
    private struct LinkRenderResult {
        let rendered: String
        let endIndex: Int
    }

    /// 从 `[` 位置尝试解析 `[text](url)` 格式的内联链接。
    ///
    /// 成功时返回渲染后的字符串和结束索引；失败时返回 nil（让调用方按普通 `[` 处理）。
    private func parseAndRenderInlineLink(chars: [Character], startIndex: Int) -> LinkRenderResult? {
        // 1. 找到匹配的 `]`
        guard let closeBracket = findMatchingCloseBracket(chars: chars, openIndex: startIndex) else {
            return nil
        }

        let text = String(chars[(startIndex + 1)..<closeBracket])
        guard !text.isEmpty else { return nil }

        // 2. `]` 后必须紧跟 `(`
        let afterCloseBracket = closeBracket + 1
        guard afterCloseBracket < chars.count && chars[afterCloseBracket] == "(" else {
            return nil
        }

        // 3. 找到匹配的 `)`
        let openParen = afterCloseBracket
        guard let closeParen = findMatchingCloseParen(chars: chars, openIndex: openParen) else {
            return nil
        }

        let url = String(chars[(openParen + 1)..<closeParen])
        guard !url.isEmpty else { return nil }

        // 4. 渲染链接
        let rendered = renderInlineLink(text: text, url: url)
        return LinkRenderResult(rendered: rendered, endIndex: closeParen + 1)
    }

    /// 在字符数组中找到匹配的 `]`（处理嵌套 `[`）。
    private func findMatchingCloseBracket(chars: [Character], openIndex: Int) -> Int? {
        var depth = 1
        var i = openIndex + 1
        while i < chars.count {
            if chars[i] == "[" {
                depth += 1
            } else if chars[i] == "]" {
                depth -= 1
                if depth == 0 { return i }
            } else if chars[i] == "`" {
                // 跳过内联代码内容
                i += 1
                while i < chars.count && chars[i] != "`" { i += 1 }
            }
            i += 1
        }
        return nil
    }

    /// 在字符数组中找到匹配的 `)`（处理嵌套 `(`）。
    private func findMatchingCloseParen(chars: [Character], openIndex: Int) -> Int? {
        var depth = 1
        var i = openIndex + 1
        while i < chars.count {
            if chars[i] == "(" {
                depth += 1
            } else if chars[i] == ")" {
                depth -= 1
                if depth == 0 { return i }
            }
            // URL 中的空格意味着这不是有效的 Markdown 链接
            if chars[i] == " " { return nil }
            i += 1
        }
        return nil
    }

    /// 渲染内联链接 — 颜色文本 + 可选 OSC 8 超链接。
    ///
    /// 有 OSC 8 支持：`ESC]8;;urlBELcolored textESC]8;;BEL`
    /// 无 OSC 8 支持：`colored text (url)`（展示 URL）
    private func renderInlineLink(text: String, url: String) -> String {
        let (linkColor, resetCode) = linkColorCodes()

        if let formatter = hyperlinkFormatter, formatter.supportsOSC8 {
            // OSC 8 可点击超链接
            let coloredText = "\(linkColor)\(text)\(resetCode)"
            return formatter.formatURL(url, visibleText: coloredText)
        } else {
            // 无 OSC 8 支持 — 着色文本 + dim URL
            let (dimCode, dimReset) = dimCodes()
            return "\(linkColor)\(text)\(resetCode) \(dimCode)(\(url))\(dimReset)"
        }
    }

    // MARK: - Image Parsing & Rendering

    /// 图片解析结果（内部使用）
    private struct ImageRenderResult {
        let rendered: String
        let endIndex: Int
    }

    /// 从 `![` 位置尝试解析 `![alt](url)` 格式的图片语法。
    ///
    /// 成功时返回渲染后的字符串和结束索引；失败时返回 nil（让调用方按普通 `!` + `[` 处理）。
    private func parseAndRenderImage(chars: [Character], startIndex: Int) -> ImageRenderResult? {
        // startIndex 指向 `!`，下一个字符应该是 `[`
        guard startIndex + 1 < chars.count && chars[startIndex + 1] == "[" else {
            return nil
        }

        // 1. 找到匹配的 `]`（从 `[` 位置开始搜索）
        guard let closeBracket = findMatchingCloseBracket(chars: chars, openIndex: startIndex + 1) else {
            return nil
        }

        let alt = String(chars[(startIndex + 2)..<closeBracket])

        // 2. `]` 后必须紧跟 `(`
        let afterCloseBracket = closeBracket + 1
        guard afterCloseBracket < chars.count && chars[afterCloseBracket] == "(" else {
            return nil
        }

        // 3. 找到匹配的 `)`
        let openParen = afterCloseBracket
        guard let closeParen = findMatchingCloseParen(chars: chars, openIndex: openParen) else {
            return nil
        }

        let url = String(chars[(openParen + 1)..<closeParen])

        // 4. 渲染图片占位 — `[📷 alt]` 格式
        let rendered = renderImage(alt: alt, url: url)
        return ImageRenderResult(rendered: rendered, endIndex: closeParen + 1)
    }

    /// 渲染图片语法 — `[📷 alt]` 格式。
    ///
    /// 有 OSC 8 支持：`[📷 alt]` 作为可点击超链接指向图片 URL
    /// 无 OSC 8 支持：`[📷 alt]` 着色文本
    private func renderImage(alt: String, url: String) -> String {
        let (linkColor, resetCode) = linkColorCodes()
        let displayAlt = alt.isEmpty ? "image" : alt

        if let formatter = hyperlinkFormatter, formatter.supportsOSC8 {
            // OSC 8 可点击超链接
            let coloredText = "\(linkColor)[📷 \(displayAlt)]\(resetCode)"
            return formatter.formatURL(url, visibleText: coloredText)
        } else {
            // 无 OSC 8 — 着色图片占位符
            return "\(linkColor)[📷 \(displayAlt)]\(resetCode)"
        }
    }

    // MARK: - ANSI Code Helpers

    /// 粗体开始/结束代码
    private func boldCodes() -> (on: String, off: String) {
        switch profile {
        case .trueColor, .ansi256, .ansi16:
            return (on: "\u{1B}[1m", off: "\u{1B}[0m")
        case .unknown:
            return (on: "", off: "")
        }
    }

    /// 粗体切换代码（用于内联格式化）
    private func boldToggleCodes() -> (on: String, off: String) {
        switch profile {
        case .trueColor, .ansi256, .ansi16:
            return (on: "\u{1B}[1m", off: "\u{1B}[0m")
        case .unknown:
            return (on: "", off: "")
        }
    }

    /// 斜体切换代码。
    ///
    /// ANSI 终端支持两种斜体表示：
    /// - `ESC[3m` → italic 属性（大多数现代终端支持）
    /// - 降级为 dim + 颜色偏移（保守回退）
    private func italicToggleCodes() -> (on: String, off: String) {
        switch profile {
        case .trueColor:
            // 精确 RGB 斜体色：淡紫粉色调，与粗体/代码形成视觉区分
            return (on: "\u{1B}[3m\u{1B}[38;2;203;166;247m", off: "\u{1B}[0m")
        case .ansi256:
            return (on: "\u{1B}[3m\u{1B}[38;5;183m", off: "\u{1B}[0m")
        case .ansi16:
            return (on: "\u{1B}[3m", off: "\u{1B}[0m")
        case .unknown:
            return (on: "", off: "")
        }
    }

    /// 列表标记颜色代码 — 用于编号和 bullet 着色。
    private func listMarkerCodes() -> (color: String, reset: String) {
        switch profile {
        case .trueColor:
            return ("\u{1B}[38;2;250;204;21m", "\u{1B}[0m")    // 黄色（与 tool role 一致）
        case .ansi256:
            return ("\u{1B}[38;5;220m", "\u{1B}[0m")
        case .ansi16:
            return ("\u{1B}[33m", "\u{1B}[0m")                  // yellow
        case .unknown:
            return ("", "")
        }
    }

    /// 内联代码颜色切换代码
    private func inlineCodeToggleCodes() -> (on: String, off: String) {
        switch profile {
        case .trueColor:
            // 柔和的青绿色，区别于代码块边框的紫蓝色
            return (on: "\u{1B}[38;2;110;231;183m", off: "\u{1B}[0m")
        case .ansi256:
            return (on: "\u{1B}[38;5;121m", off: "\u{1B}[0m")
        case .ansi16:
            return (on: "\u{1B}[36m", off: "\u{1B}[0m")  // cyan
        case .unknown:
            return (on: "", off: "")
        }
    }

    /// 删除线颜色切换代码 — strikethrough ANSI 属性 + dim 颜色
    private func strikethroughToggleCodes() -> (on: String, off: String) {
        switch profile {
        case .trueColor:
            // strikethrough 属性 + dim 灰红色
            return (on: "\u{1B}[9m\u{1B}[38;2;140;120;120m", off: "\u{1B}[0m")
        case .ansi256:
            return (on: "\u{1B}[9m\u{1B}[38;5;138m", off: "\u{1B}[0m")
        case .ansi16:
            // strikethrough 属性 + dim（ANSI16 没有 strikethrough 颜色）
            return (on: "\u{1B}[9m\u{1B}[2m", off: "\u{1B}[0m")
        case .unknown:
            return (on: "", off: "")
        }
    }

    /// 任务列表复选框颜色代码 — 已勾选绿色 / 未勾选 dim 灰色
    private func taskListMarkerCodes(checked: Bool) -> (color: String, reset: String) {
        if checked {
            switch profile {
            case .trueColor:
                return ("\u{1B}[38;2;76;175;80m", "\u{1B}[0m")  // 绿色（与 DiffFormatter 一致）
            case .ansi256:
                return ("\u{1B}[38;5;71m", "\u{1B}[0m")
            case .ansi16:
                return ("\u{1B}[32m", "\u{1B}[0m")
            case .unknown:
                return ("", "")
            }
        } else {
            switch profile {
            case .trueColor:
                return ("\u{1B}[38;2;120;120;140m", "\u{1B}[0m")  // dim 灰色
            case .ansi256:
                return ("\u{1B}[38;5;244m", "\u{1B}[0m")
            case .ansi16:
                return ("\u{1B}[2m", "\u{1B}[0m")  // dim
            case .unknown:
                return ("", "")
            }
        }
    }

    /// 内联链接文本颜色代码 — 蓝色下划线风格
    private func linkColorCodes() -> (color: String, reset: String) {
        switch profile {
        case .trueColor:
            return ("\u{1B}[38;2;96;165;250m", "\u{1B}[0m")  // 天蓝色（与 H2 标题一致）
        case .ansi256:
            return ("\u{1B}[38;5;111m", "\u{1B}[0m")
        case .ansi16:
            return ("\u{1B}[34m", "\u{1B}[0m")  // blue
        case .unknown:
            return ("", "")
        }
    }

    /// Dim 颜色代码（用于分割线）
    private func dimCodes() -> (code: String, reset: String) {
        switch profile {
        case .trueColor:
            return ("\u{1B}[38;2;100;100;120m", "\u{1B}[0m")
        case .ansi256:
            return ("\u{1B}[38;5;243m", "\u{1B}[0m")
        case .ansi16:
            return ("\u{1B}[2m", "\u{1B}[0m")
        case .unknown:
            return ("", "")
        }
    }
}
