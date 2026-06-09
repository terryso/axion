import Foundation

/// 流式 Markdown 内联格式化器 — Codex 启发，增强 LLM 流式输出中非代码文本的可读性。
///
/// 处理的 Markdown 元素：
/// - 标题（`#` ~ `####`）→ 粗体 + 颜色
/// - 粗体（`**text**`）→ 明亮/粗体 ANSI
/// - 斜体（`*text*`、`_text_`）→ italic ANSI
/// - 内联代码（`` `code` ``）→ 独立颜色高亮
/// - 水平分割线（`---`、`***`、`___`）→ Unicode 可视化分隔线
/// - 有序列表（`1. text`）→ 彩色编号 + 缩进
/// - 无序列表（`- text`、`* text`、`+ text`）→ 彩色符号 + 缩进
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

    init(
        profile: TerminalColorProfile = TerminalColorProfile.detect(),
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        terminalWidth: Int = 80
    ) {
        self.profile = isTTY ? profile : .unknown
        self.isTTY = isTTY
        self.terminalWidth = terminalWidth
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

        // 4. 列表项
        if let list = parseList(trimmed) {
            return renderList(originalLine: line, marker: list.marker, text: list.text)
        }

        // 5. 内联元素（粗体 + 斜体 + 内联代码）
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

    // MARK: - Rendering

    /// 渲染水平分割线 — dim 色 Unicode 线
    private func renderHorizontalRule() -> String {
        let (dimCode, resetCode) = dimCodes()
        let line = String(repeating: "─", count: terminalWidth)
        return "\(dimCode)\(line)\(resetCode)"
    }

    /// 渲染标题 — 粗体 + 级别相关颜色
    private func renderHeading(originalLine: String, level: Int, text: String) -> String {
        let (boldCode, resetCode) = boldCodes()
        let colorCode = headingColor(level: level)

        // 保留原始行的前导空格缩进
        let leadingSpaces = originalLine.prefix(while: { $0 == " " })
        let hashPrefix = String(repeating: "#", count: level)

        // 格式化文本（处理内联元素）
        let formattedText = formatInlineElements(text)

        return "\(leadingSpaces)\(colorCode)\(boldCode)\(hashPrefix)\(resetCode) \(formattedText)"
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

    /// 格式化行内 Markdown 元素（粗体 + 斜体 + 内联代码）。
    ///
    /// 扫描策略：逐字符扫描，维护粗体/斜体/代码开关状态。
    /// - `**text**` → 粗体开关（ANSI bold）
    /// - `*text*` → 斜体开关（ANSI italic）
    /// - `_text_` → 斜体开关（ANSI italic）
    /// - `` `code` `` → 内联代码开关（ANSI 颜色）
    ///
    /// 注意：`*` 优先匹配 `**`（粗体），单 `*` 在非粗体上下文中视为斜体。
    /// 检测顺序：`**` → `` ` `` → `*` → `_`。
    private func formatInlineElements(_ line: String) -> String {
        guard isTTY && profile != .unknown else { return line }

        // 快速路径：不含任何格式标记的行直接返回
        let needsFormatting = line.contains("**") || line.contains("`")
            || line.contains("*") || line.contains("_")
        guard needsFormatting else { return line }

        var result = ""
        let chars = Array(line)
        var i = 0
        var inBold = false
        var inItalic = false
        var inCode = false

        let (boldOn, boldOff) = boldToggleCodes()
        let (italicOn, italicOff) = italicToggleCodes()
        let (codeOn, codeOff) = inlineCodeToggleCodes()

        while i < chars.count {
            // 检测 `**` 粗体标记（优先级最高，避免误匹配为斜体）
            if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "*" && !inCode {
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
            if chars[i] == "`" && !inBold {
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

            // 检测 `*` 斜体标记（仅在非粗体、非代码上下文）
            if chars[i] == "*" && !inBold && !inCode {
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
            if chars[i] == "_" && !inBold && !inCode {
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
        if inBold || inItalic || inCode {
            result += "\u{1B}[0m"
        }

        return result
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
