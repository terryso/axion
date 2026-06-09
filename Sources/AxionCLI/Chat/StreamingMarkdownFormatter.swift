import Foundation

/// 流式 Markdown 内联格式化器 — Codex 启发，增强 LLM 流式输出中非代码文本的可读性。
///
/// 处理的 Markdown 元素：
/// - 标题（`#` ~ `####`）→ 粗体 + 颜色
/// - 粗体（`**text**`）→ 明亮/粗体 ANSI
/// - 内联代码（`` `code` ``）→ 独立颜色高亮
/// - 水平分割线（`---`、`***`、`___`）→ Unicode 可视化分隔线
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
    /// 3. 内联元素（粗体 `**text**` + 内联代码 `` `code` ``）
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

        // 3. 内联元素（粗体 + 内联代码）
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

    /// 格式化行内 Markdown 元素（粗体 + 内联代码）。
    ///
    /// 扫描策略：逐字符扫描，维护粗体/代码开关状态。
    /// - `**text**` → 粗体开关（ANSI bold）
    /// - `` `code` `` → 内联代码开关（ANSI 颜色）
    private func formatInlineElements(_ line: String) -> String {
        guard isTTY && profile != .unknown else { return line }
        guard line.contains("**") || line.contains("`") else { return line }

        var result = ""
        let chars = Array(line)
        var i = 0
        var inBold = false
        var inCode = false

        let (boldOn, boldOff) = boldToggleCodes()
        let (codeOn, codeOff) = inlineCodeToggleCodes()

        while i < chars.count {
            // 检测 `**` 粗体标记
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

            // 检测 `` ` `` 内联代码标记
            if chars[i] == "`" && !inBold {
                if inCode {
                    result += codeOff
                    inCode = false
                } else {
                    result += codeOn
                    inCode = true
                }
                i += 1
                continue
            }

            result += String(chars[i])
            i += 1
        }

        // 如果有未关闭的样式，追加 reset
        if inBold || inCode {
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
