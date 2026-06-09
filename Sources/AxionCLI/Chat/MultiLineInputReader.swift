import Foundation

/// 多行输入读取器 — 支持反斜杠续行和 bracket paste 多行粘贴。
///
/// 在 TTY 模式下：
/// - **反斜杠续行**：行末 `\` + 回车 → 累积续行，显示 `...>` 提示符
/// - **Bracket Paste**：检测 `\x1b[200~...\x1b[201~` 包裹的粘贴内容，合并为单条输入
/// - **续行取消**：续行模式下空行输入 → 返回空字符串 `""`
///
/// 非 TTY 模式（管道/重定向）下直接调用 `readLine()`，不处理上述功能。
///
/// 所有外部依赖（`isatty`、`readLine`、`fputs`）通过构造器注入，便于测试。
struct MultiLineInputReader {

    /// Bracket paste 开始标记
    private static let pasteStart = "\u{1B}[200~"
    /// Bracket paste 结束标记
    private static let pasteEnd = "\u{1B}[201~"

    /// 是否连接到 TTY
    let isTTY: Bool

    /// 读取单行输入的闭包（注入，默认为 `readLine(strippingNewline:)`）
    let readLineFn: () -> String?

    /// 输出到 stdout 的闭包（注入，默认为 `fputs(, stdout)`）
    let writeStdout: (String) -> Void

    /// 输出到 stderr 的闭包（注入，默认为 `fputs(, stderr)`）
    let writeStderr: (String) -> Void

    /// CJK 检测闭包（注入，默认为 `CJKInputHandler.isCJKEnabled`）
    /// 生产环境检测终端 UTF-8 支持，测试中注入 false 跳过 raw mode 路径
    let cjkEnabledFn: () -> Bool

    // MARK: - Init

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        readLineFn: @escaping () -> String? = { readLine(strippingNewline: true) },
        writeStdout: @escaping (String) -> Void = { fputs($0, stdout); fflush(stdout) },
        writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) },
        cjkEnabledFn: @escaping () -> Bool = { CJKInputHandler.isCJKEnabled() }
    ) {
        self.isTTY = isTTY
        self.readLineFn = readLineFn
        self.writeStdout = writeStdout
        self.writeStderr = writeStderr
        self.cjkEnabledFn = cjkEnabledFn
    }

    // MARK: - Public API

    /// 读取用户输入，支持多行续行和 bracket paste。
    ///
    /// - Parameters:
    ///   - prompt: 主提示符（如 `axion> `）
    ///   - continuationPrompt: 续行提示符（如 `...> `）
    /// - Returns:
    ///   - `String?` 非 nil = 用户输入内容
    ///   - `nil` = EOF（stdin 关闭）
    ///   - `""` (空字符串) = 续行取消（用户在续行模式按了空行）
    func readInput(prompt: String, continuationPrompt: String) -> String? {
        // 非 TTY 模式：直接返回 readLine 结果，不输出提示符
        guard isTTY else {
            return readLineFn()
        }

        // TTY + UTF-8 环境：使用 CJKInputHandler 的 raw mode 输入
        // 确保 backspace 正确删除完整 UTF-8 字符（中文、emoji 等）
        if cjkEnabledFn() {
            return readCJKInput(prompt: prompt, continuationPrompt: continuationPrompt)
        }

        // TTY 模式（非 UTF-8 终端）：显示主提示符
        writeStdout(prompt)
        let firstLine = readLineFn()

        // EOF
        guard let line = firstLine else {
            return nil
        }

        // 检测 bracket paste
        if line.hasPrefix(Self.pasteStart) {
            return readBracketPaste(firstLine: line)
        }

        // 检测反斜杠续行
        if line.hasSuffix("\\") {
            return readContinuationLoop(accumulated: String(line.dropLast())) {
                self.writeStdout(continuationPrompt)
                return self.readLineFn()
            }
        }

        // 普通输入
        return line
    }

    /// 启用终端 bracket paste mode（向 stderr 输出 `\x1b[?2004h`）。
    /// 非 TTY 模式下不输出。
    func enableBracketPaste() {
        guard isTTY else { return }
        writeStderr("\u{1B}[?2004h")
    }

    /// 禁用终端 bracket paste mode（向 stderr 输出 `\x1b[?2004l`）。
    /// 非 TTY 模式下不输出。
    func disableBracketPaste() {
        guard isTTY else { return }
        writeStderr("\u{1B}[?2004l")
    }

    // MARK: - CJK Raw Mode Input

    /// 使用 CJK raw mode 读取输入，支持反斜杠续行。
    ///
    /// 与非 CJK 路径逻辑一致：检测行末 `\` → 续行，空行取消续行。
    private func readCJKInput(prompt: String, continuationPrompt: String) -> String? {
        guard let firstLine = CJKInputHandler.readRawLine(
            prompt: prompt,
            writeStdout: writeStdout
        ) else { return nil }

        // 检测反斜杠续行（与非 CJK 路径一致的逻辑）
        if firstLine.hasSuffix("\\") {
            return readContinuationLoop(accumulated: String(firstLine.dropLast())) {
                CJKInputHandler.readRawLine(prompt: continuationPrompt, writeStdout: self.writeStdout)
            }
        }

        return firstLine
    }

    // MARK: - Bracket Paste

    /// 读取 bracket paste 内容。
    ///
    /// 粘贴的多行内容被 `readLine()` 在 `\n` 处拆分成多次调用。
    /// 策略：累积每一行，直到遇到以 `\x1b[201~` 结尾的行。
    private func readBracketPaste(firstLine: String) -> String {
        // 去除开头的 paste start 标记
        let firstContent = String(firstLine.dropFirst(Self.pasteStart.count))

        // 检查是否单行就包含了 paste end
        if firstContent.hasSuffix(Self.pasteEnd) {
            let content = String(firstContent.dropLast(Self.pasteEnd.count))
            return content
        }

        // 多行累积
        var lines = [firstContent]
        while let nextLine = readLineFn() {
            if nextLine.hasSuffix(Self.pasteEnd) {
                let lastContent = String(nextLine.dropLast(Self.pasteEnd.count))
                if !lastContent.isEmpty {
                    lines.append(lastContent)
                }
                break
            }
            lines.append(nextLine)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Shared Continuation Loop

    /// 读取续行输入的共享循环，TTY 和 CJK raw mode 路径共用。
    ///
    /// - Parameters:
    ///   - accumulated: 已累积的内容（已去除末尾反斜杠）
    ///   - readNextLine: 读取下一行的闭包（TTY 用 readLineFn，CJK 用 readRawLine）
    /// - Returns:
    ///   - 合并后的完整字符串
    ///   - `""` 空字符串表示续行取消
    private func readContinuationLoop(
        accumulated: String,
        readNextLine: () -> String?
    ) -> String {
        var parts = [accumulated]

        while true {
            guard let line = readNextLine() else {
                // EOF：返回已累积内容
                return parts.joined(separator: "\n")
            }

            // 续行取消：空行输入
            if line.isEmpty { return "" }

            // 继续续行：行末有反斜杠
            if line.hasSuffix("\\") {
                parts.append(String(line.dropLast()))
                continue
            }

            // 正常结束
            parts.append(line)
            return parts.joined(separator: "\n")
        }
    }
}
