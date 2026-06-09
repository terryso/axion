/// 流式代码块视觉渲染器 — Codex 启发，在 LLM 流式输出中检测 markdown 代码围栏，
/// 并用视觉边框替代原始 ``` 标记，提升代码块可读性。
///
/// 设计原则：
/// - 纯状态机，不持有 I/O（写入由调用方控制）
/// - 在行边界处检测代码围栏（```），渲染可视化边框
/// - 支持 TrueColor/ANSI256/ANSI16/unknown 全部颜色 profile 降级
/// - 非 TTY 环境下原样输出（不渲染边框）
/// - 跨 chunk 缓冲不完整行，确保围栏检测不遗漏
///
/// 状态机：
/// ```
/// idle ──(检测到 ``` + lang)──► inCodeBlock(lang)
///   ▲                                  │
///   └────(检测到 ```)─────────────────┘
/// ```
struct StreamingCodeBlockRenderer: Sendable {
    /// 当前是否处于代码块内
    private(set) var inCodeBlock = false

    /// 当前代码块语言标签（可能为空）
    private(set) var currentLang = ""

    /// 行缓冲区 — 累积不完整行（未以 \n 结尾的 chunk）
    private var lineBuffer = ""

    /// 终端颜色 profile（影响边框颜色）
    private let profile: TerminalColorProfile

    /// 是否为 TTY 环境
    private let isTTY: Bool

    /// 终端宽度（用于边框长度计算）
    private let terminalWidth: Int

    /// 纯文本行格式化器（用于增强非代码块内的 Markdown 输出）
    private let plainTextFormatter: @Sendable (String) -> String

    init(
        profile: TerminalColorProfile = TerminalColorProfile.detect(),
        isTTY: Bool = false,
        terminalWidth: Int = 80,
        plainTextFormatter: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.profile = profile
        self.isTTY = isTTY
        self.terminalWidth = terminalWidth
        self.plainTextFormatter = plainTextFormatter
    }

    // MARK: - Public API

    /// 处理流式文本 chunk，检测代码围栏并渲染视觉边框。
    ///
    /// 文本按行拆分处理：
    /// - 不完整行（不以 \n 结尾）缓冲到 `lineBuffer`
    /// - 完整行检查是否匹配代码围栏标记
    /// - 围栏标记替换为视觉边框输出
    /// - 非围栏内容原样输出
    ///
    /// - Parameters:
    ///   - text: 流式文本 chunk
    ///   - write: 输出闭包（由调用方决定输出目标）
    mutating func process(_ text: String, write: (String) -> Void) {
        guard isTTY && !text.isEmpty else {
            // 非 TTY 或空文本直接输出
            if !text.isEmpty { write(text) }
            return
        }

        // 将新文本追加到行缓冲区
        lineBuffer += text

        // 按行拆分处理
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.lowerBound...].dropFirst())

            processCompleteLine(line, write: write)
            write("\n")
        }

        // 检查缓冲区是否包含完整的代码围栏行（不以换行结尾但本身是围栏标记）
        // 这处理 ``` 出现在 chunk 末尾但未带 \n 的情况
        if !lineBuffer.isEmpty && isFenceLine(lineBuffer) {
            let line = lineBuffer
            lineBuffer = ""
            processCompleteLine(line, write: write)
            write("\n")
        }
    }

    /// 在 turn 结束时调用（`.assistant` / `.result` 事件），清空缓冲区和状态。
    mutating func reset() {
        inCodeBlock = false
        currentLang = ""
        lineBuffer = ""
    }

    /// 刷新缓冲区中剩余的内容（用于 turn 结束时确保所有文本已输出）。
    mutating func flush(write: (String) -> Void) {
        if !lineBuffer.isEmpty {
            // 如果还在代码块内，可能是 LLM 忘记关闭的围栏
            // 先处理缓冲区中的内容
            processCompleteLine(lineBuffer, write: write)
            lineBuffer = ""
        }
    }

    // MARK: - Line Processing

    /// 处理一行完整文本（不含末尾 \n）。
    private mutating func processCompleteLine(_ line: String, write: (String) -> Void) {
        if isFenceLine(line) {
            if inCodeBlock {
                // 结束代码块 — 渲染底部边框
                write(renderCloseBorder())
                inCodeBlock = false
                currentLang = ""
            } else {
                // 开始代码块 — 提取语言标签并渲染顶部边框
                currentLang = extractLanguage(from: line)
                write(renderOpenBorder(lang: currentLang))
                inCodeBlock = true
            }
        } else if inCodeBlock {
            // 代码块内内容 — 渲染为 dim 样式
            write(renderCodeContent(line))
        } else {
            // 普通文本 — 通过 Markdown 格式化器增强输出
            write(plainTextFormatter(line))
        }
    }

    // MARK: - Fence Detection

    /// 检测一行是否为代码围栏标记（以 3+ 个反引号或 ~ 开头）。
    private func isFenceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // 匹配 3+ 个反引号或 ~
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            // 确保围栏标记后只有语言标签（没有代码内容）
            let fenceChar = trimmed.first!
            let fenceCount = trimmed.prefix(while: { $0 == fenceChar }).count
            guard fenceCount >= 3 else { return false }
            // 围栏后剩余部分应该只是语言标签（字母、数字、+、-、.）
            let afterFence = trimmed.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces)
            return afterFence.isEmpty || afterFence.allSatisfy { c in
                c.isLetter || c.isNumber || c == "+" || c == "-" || c == "." || c == "_"
            }
        }
        return false
    }

    /// 从围栏行提取语言标签。
    private func extractLanguage(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let fenceChar = trimmed.first!
        let fenceCount = trimmed.prefix(while: { $0 == fenceChar }).count
        let lang = trimmed.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces)
        return lang
    }

    // MARK: - Visual Border Rendering

    /// 渲染代码块顶部边框 — 包含语言标签。
    ///
    /// 格式示例（TTY）：`╭── swift ──────────────────────╮`
    /// 非 TTY/unknown：`── swift ──`
    private func renderOpenBorder(lang: String) -> String {
        let (openBorder, closeBorder, midBorder, dimCode, resetCode) = borderStyles()

        if lang.isEmpty {
            let innerWidth = terminalWidth - 2  // 减去两侧边框字符
            let line = String(repeating: midBorder, count: max(innerWidth, 10))
            return "\(dimCode)\(openBorder)\(line)\(closeBorder)\(resetCode)"
        }

        // 带语言标签的边框
        let label = " \(lang) "
        let labelCount = label.count
        let leftBars = String(repeating: midBorder, count: 2)
        let remainingWidth = max(terminalWidth - 2 - leftBars.count - labelCount, 0)
        let rightBars = String(repeating: midBorder, count: remainingWidth)

        return "\(dimCode)\(openBorder)\(leftBars)\(resetCode)\(langCode())\(label)\(resetCode)\(dimCode)\(rightBars)\(closeBorder)\(resetCode)"
    }

    /// 渲染代码块底部边框。
    ///
    /// 格式示例（TTY）：`╰──────────────────────────────╯`
    /// 非 TTY/unknown：`──────────`
    private func renderCloseBorder() -> String {
        let (_, _, midBorder, dimCode, resetCode) = borderStyles()
        let innerWidth = terminalWidth - 2
        let line = String(repeating: midBorder, count: max(innerWidth, 10))
        return "\(dimCode)╰\(line)╯\(resetCode)"
    }

    /// 渲染代码块内的一行内容 — 使用 dim 样式。
    private func renderCodeContent(_ line: String) -> String {
        let (dimCode, resetCode) = dimStyles()
        return "\(dimCode)│ \(resetCode)\(line)"
    }

    // MARK: - Style Helpers

    /// 返回边框字符和颜色代码的元组。
    private func borderStyles() -> (open: String, close: String, mid: String, dimCode: String, resetCode: String) {
        let dimCode: String
        switch profile {
        case .trueColor:
            dimCode = "\u{1B}[38;2;100;100;120m"
        case .ansi256:
            dimCode = "\u{1B}[38;5;243m"
        case .ansi16:
            dimCode = "\u{1B}[2m"
        case .unknown:
            dimCode = ""
        }
        let resetCode = dimCode.isEmpty ? "" : "\u{1B}[0m"
        return (open: "╭", close: "╮", mid: "─", dimCode: dimCode, resetCode: resetCode)
    }

    /// 返回代码内容的 dim 样式。
    private func dimStyles() -> (dimCode: String, resetCode: String) {
        let dimCode: String
        switch profile {
        case .trueColor:
            dimCode = "\u{1B}[38;2;100;100;120m"
        case .ansi256:
            dimCode = "\u{1B}[38;5;243m"
        case .ansi16:
            dimCode = "\u{1B}[2m"
        case .unknown:
            dimCode = ""
        }
        let resetCode = dimCode.isEmpty ? "" : "\u{1B}[0m"
        return (dimCode: dimCode, resetCode: resetCode)
    }

    /// 返回语言标签的颜色代码（青色）。
    private func langCode() -> String {
        switch profile {
        case .trueColor:
            return "\u{1B}[38;2;129;140;248m"  // 紫蓝色（与 KeyHintsFormatter 一致）
        case .ansi256:
            return "\u{1B}[38;5;104m"
        case .ansi16:
            return "\u{1B}[36m"  // cyan
        case .unknown:
            return ""
        }
    }
}
