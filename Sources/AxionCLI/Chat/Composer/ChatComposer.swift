import Foundation

/// 轻量 Composer — 替代 MultiLineInputReader 作为 Chat REPL 的输入组件。
///
/// 职责：
/// 1. Raw mode 事件循环（通过 KeyEventReader）处理所有按键事件
/// 2. 非 TTY / raw mode 失败时自动降级到 MultiLineInputReader
/// 3. 反斜杠续行（从 MultiLineInputReader 迁移，统一 raw mode + 降级路径）
/// 4. Bracket paste 多行粘贴
/// 5. Esc 清空 / 模式切换 + draft 恢复
/// 6. 快捷键响应（Up/Down/Ctrl+R 等 — 暂不实现功能，不吞键）
///
/// 所有输出通过注入的 `writeStdout`/`writeStderr` 闭包（纯函数 + DI 模式）。
///
/// 模式处理逻辑提取到独立 extension 文件：
/// - `ComposerSlashPopupHandling` — 斜杠命令补全弹出层
/// - `ComposerHistorySearchHandling` — 历史搜索模式
/// - `ComposerFileSearchHandling` — 文件搜索模式
/// - `ComposerHistoryNavigation` — 历史上下导航
/// - `ComposerQuickActions` — 输入排队 + 外部编辑器
struct ChatComposer {

    /// 最大单行输入长度（字节），防止超长行导致回显问题
    static let maxInputLength = 4096

    // MARK: - Dependencies

    /// 按键读取器（nil = 降级路径）
    let keyReader: (any KeyReading)?
    /// 是否连接到 TTY
    let isTTY: Bool
    /// 输出到 stdout
    let writeStdout: (String) -> Void
    /// 输出到 stderr
    let writeStderr: (String) -> Void
    /// 降级路径的 readLine（非 TTY 使用）
    let readLineFn: () -> String?

    // MARK: - State (per-readInput call)

    /// 当前编辑缓冲区
    var buffer: String = ""
    /// 光标位置（字符偏移量）
    var cursor: Int = 0
    /// 当前交互模式
    var mode: ComposerMode = .normal
    /// 模式切换前保存的 draft
    var savedDraft: ComposerDraft?

    /// KeyEventReader 实例（需要手动恢复 termios）
    var ownedKeyReader: KeyEventReader?

    // MARK: - Slash Popup State (AC1/AC5/AC6)

    /// 当前 popup 过滤结果
    var popupItems: [SlashPopupItem] = []
    /// popup 列表选中索引
    var selectedPopupIndex: Int = -1
    /// popup 渲染占用的行数（用于清除）
    var popupRenderedLines: Int = 0
    /// 颜色主题（lazy 初始化）
    var chatTheme: ChatTheme?
    /// Slash 上下文（agent 忙碌状态等）
    var slashContext: SlashCommandContext = SlashCommandContext(isAgentBusy: false, isSideSession: false)

    /// 外部编辑器启动器（可注入 mock，nil 时自动创建 production 实例）。
    var injectedEditorLauncher: ExternalEditorLauncher?

    // MARK: - Input Queue State (Story 38.5)

    /// 输入队列（由外部注入，ChatCommand 拥有 InputQueue 实例）
    var inputQueue: InputQueue?

    // MARK: - File Search State (Story 38.6)

    /// 文件搜索器（可注入 Mock）
    var fileSearcher: any FileSearching = FileSearcher()
    /// 搜索根目录
    var cwd: String = FileManager.default.currentDirectoryPath
    /// 文件搜索缓存结果
    var cachedFileResults: [String] = []
    /// 文件搜索总匹配数（截断前）
    var totalFileMatches: Int = 0
    /// 文件搜索选中索引
    var fileSearchSelectedIndex: Int = 0
    /// 文件搜索渲染行数
    var fileSearchRenderedLines: Int = 0
    /// 文件搜索前的草稿备份
    var fileSearchDraftBackup: ComposerDraft?

    // MARK: - History Navigation State (AC1)

    /// 会话历史（由外部注入，会话内用户发送的所有非空消息）
    var history: [String] = []
    /// 历史浏览索引（-1 = 未浏览历史）
    var historyIndex: Int = -1
    /// 浏览历史前的草稿（用于 Down 回到浏览前状态）
    var preHistoryDraft: String = ""

    // MARK: - History Search State (AC2/AC3/AC4/AC5)

    /// 当前历史搜索会话（nil = 不在搜索模式）
    var searchSession: HistorySearchSession?
    /// 搜索 footer 占用的行数（用于清除）
    var searchFooterLines: Int = 0

    // MARK: - Multi-line Display State

    /// 上一次 refreshDisplay 占用的终端物理行数。
    /// 用于在下次重绘时上移光标到正确的起始行。
    var previousDisplayLines: Int = 1

    // MARK: - Prefill State

    /// 下次 readInput 时预填到 buffer 的文本（由外部设置，readRawLoop 消费后清空）。
    /// 用于 Ctrl+C 中断后恢复上次的输入内容。
    var prefill: String? = nil

    // MARK: - Init

    init(
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        writeStdout: @escaping (String) -> Void = { fputs($0, stdout); fflush(stdout) },
        writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) },
        readLineFn: @escaping () -> String? = { readLine(strippingNewline: true) },
        keyReader: (any KeyReading)? = nil
    ) {
        self.isTTY = isTTY
        self.writeStdout = writeStdout
        self.writeStderr = writeStderr
        self.readLineFn = readLineFn
        self.keyReader = keyReader
    }

    // MARK: - Public API

    /// 读取用户输入 — 主公共 API（与 MultiLineInputReader 签名一致）。
    ///
    /// - Parameters:
    ///   - prompt: 主提示符（如动态提示符）
    ///   - continuationPrompt: 续行提示符（如 `...> `）
    /// - Returns:
    ///   - `String?` 非 nil = 用户输入内容
    ///   - `nil` = EOF（stdin 关闭）或 Ctrl+C
    ///   - `""` (空字符串) = 续行取消
    mutating func readInput(prompt: String, continuationPrompt: String) -> String? {
        // AC7: 非 TTY 降级 — 直接使用 readLine
        guard isTTY else {
            return readLineFn()
        }

        // AC8: Raw mode 降级 — 如果外部未注入 keyReader，尝试创建
        let reader: any KeyReading
        if let injected = keyReader {
            reader = injected
        } else if let created = KeyEventReader.create() {
            // 存储引用以便在 defer 中恢复 termios
            ownedKeyReader = created
            reader = created
        } else {
            // Raw mode 不可用 — 降级到 MultiLineInputReader
            writeStderr("[axion] 快捷键不可用（raw mode 设置失败），使用基础输入模式\n")
            return readDegraded(prompt: prompt, continuationPrompt: continuationPrompt)
        }

        // 确保退出时恢复 termios
        defer {
            ownedKeyReader?.restore()
            ownedKeyReader = nil
        }

        return readRawLoop(reader: reader, prompt: prompt, continuationPrompt: continuationPrompt)
    }

    /// 启用终端 bracket paste mode。
    func enableBracketPaste() {
        guard isTTY else { return }
        writeStderr("\u{1B}[?2004h")
    }

    /// 禁用终端 bracket paste mode。
    func disableBracketPaste() {
        guard isTTY else { return }
        writeStderr("\u{1B}[?2004l")
    }

    // MARK: - Raw Mode Event Loop (AC1–AC6)

    /// Raw mode 事件循环 — 逐个处理 KeyEvent。
    private mutating func readRawLoop(
        reader: any KeyReading,
        prompt: String,
        continuationPrompt: String
    ) -> String? {
        // Prefill 支持：Ctrl+C 中断后恢复上次的输入
        if let prefillText = prefill {
            buffer = prefillText
            cursor = prefillText.count
            self.prefill = nil
        } else {
            buffer = ""
            cursor = 0
        }
        mode = .normal
        savedDraft = nil
        popupItems = []
        selectedPopupIndex = -1
        popupRenderedLines = 0
        historyIndex = -1
        preHistoryDraft = ""
        searchSession = nil
        searchFooterLines = 0
        cachedFileResults = []
        totalFileMatches = 0
        fileSearchSelectedIndex = 0
        fileSearchRenderedLines = 0
        fileSearchDraftBackup = nil
        previousDisplayLines = 1

        // 显示主提示符
        writeStdout(prompt)
        // 如果有 prefill 内容，显示它
        if !buffer.isEmpty {
            writeStdout(buffer)
        }
        // 初始化：计算 prompt + buffer 的物理行数
        previousDisplayLines = Self.calculateDisplayLines(prompt: prompt, buffer: buffer)

        // Bracket paste 状态
        var inBracketPaste = false
        var pasteBuffer = ""

        while true {
            guard let event = reader.readNext() else {
                // EOF
                if inBracketPaste {
                    return pasteBuffer
                }
                return buffer.isEmpty ? nil : buffer
            }

            // AC1: slashPopup 模式下拦截按键
            if case .slashPopup = mode {
                let result = handleSlashPopupEvent(event, prompt: prompt)
                if case .returnInput(let value) = result {
                    return value
                }
                continue
            }

            // AC2/AC3/AC4/AC5: historySearch 模式下拦截按键
            if case .historySearch = mode {
                handleHistorySearchEvent(event, prompt: prompt)
                continue
            }

            // AC1/AC3/AC9: fileSearch 模式下拦截按键（Story 38.6）
            if case .fileSearch = mode {
                handleFileSearchEvent(event, prompt: prompt)
                continue
            }

            switch event {
            // AC3: Bracket paste — 累积粘贴内容
            case .bracketPasteStart:
                inBracketPaste = true
                pasteBuffer = ""
                continue

            case .bracketPasteEnd:
                inBracketPaste = false
                let result = pasteBuffer
                buffer = result
                cursor = buffer.count
                // 回显粘贴内容（多行感知）
                refreshDisplay(prompt: prompt)
                continue

            // AC1: 可打印字符
            case .printable(let char):
                if inBracketPaste {
                    pasteBuffer.append(char)
                } else {
                    if buffer.utf8.count < Self.maxInputLength {
                        insertChar(char)
                        // AC1: 任何编辑操作重置历史导航
                        historyIndex = -1

                        // AC1: 检测 "/" 触发 slashPopup（buffer 只有 "/" 时触发）
                        if char == "/" && buffer == "/" {
                            enterSlashPopup(prompt: prompt)
                        } else if char == "@" && mode.isNormal && buffer == "@" {
                            // AC1 (Story 38.6): @ 触发文件搜索模式
                            enterFileSearch(prompt: prompt)
                        } else {
                            refreshDisplay(prompt: prompt)
                        }
                    }
                }

            // AC1/AC2: Enter
            case .enter:
                if inBracketPaste {
                    // Bracket paste 中换行符作为内容
                    pasteBuffer.append("\n")
                    continue
                }

                // AC2: 反斜杠续行检测
                if buffer.hasSuffix("\\") {
                    buffer = String(buffer.dropLast())
                    cursor = buffer.count
                    writeStdout("\r\n")
                    let result = readContinuationRaw(
                        reader: reader,
                        accumulated: buffer,
                        prompt: continuationPrompt
                    )
                    return result
                }

                // 正常提交
                writeStdout("\r\n")
                return buffer

            // AC1: Backspace
            case .backspace:
                if !buffer.isEmpty {
                    deleteCharBackward()
                    // AC1: 任何编辑操作重置历史导航
                    historyIndex = -1
                    refreshDisplay(prompt: prompt)
                }

            // Delete
            case .delete:
                if cursor < buffer.count {
                    deleteCharForward()
                    refreshDisplay(prompt: prompt)
                }

            // AC5/AC6: Esc
            case .escape:
                if mode.isNormal {
                    // Normal 模式：清空 buffer
                    buffer = ""
                    cursor = 0
                    refreshDisplay(prompt: prompt)
                } else {
                    // 非 normal 模式：恢复 draft + 回到 normal
                    if let draft = savedDraft {
                        let restored = draft.restore()
                        buffer = restored.text
                        cursor = restored.cursor
                        savedDraft = nil
                    }
                    mode = .normal
                    refreshDisplay(prompt: prompt)
                }

            // AC1: Up/Down 历史导航
            case .up:
                // AC1: 空 buffer 或已在历史浏览中时触发
                if !history.isEmpty && (buffer.isEmpty || historyIndex >= 0) {
                    navigateHistory(direction: .older, prompt: prompt)
                }

            case .down:
                // AC1: 已在历史浏览中时触发
                if historyIndex >= 0 {
                    navigateHistory(direction: .newer, prompt: prompt)
                }

            // AC2: Ctrl+R 进入历史搜索
            case .ctrl("r"):
                if !history.isEmpty {
                    enterHistorySearch(prompt: prompt)
                }

            // AC6: Ctrl+G 外部编辑器
            case .ctrl("g"):
                handleExternalEditor(prompt: prompt)

            // Story 38.5 AC3: Ctrl+E 弹出最近排队消息到 buffer 可编辑
            case .ctrl("e"):
                handleCtrlE(prompt: prompt)

            // Story 38.5: Ctrl+Q 将当前 buffer 入队
            case .ctrl("q"):
                handleCtrlQ(prompt: prompt)

            case .ctrl("c"):
                // Ctrl+C — 由 SignalHandler 处理，这里返回 nil
                writeStdout("\r\n")
                return nil

            case .tab:
                break

            // 光标移动（保留，后续 Story 扩展）
            case .left:
                if cursor > 0 {
                    cursor -= 1
                    refreshDisplay(prompt: prompt)
                }

            case .right:
                if cursor < buffer.count {
                    cursor += 1
                    refreshDisplay(prompt: prompt)
                }

            // EOF — 终止输入
            case .eof:
                if buffer.isEmpty {
                    return nil
                }
                // 非空 buffer 时返回已输入内容
                writeStdout("\r\n")
                return buffer

            // 其他 Ctrl 键 — 不吞键但不做操作
            case .ctrl:
                break

            // 未知序列 — 忽略
            case .unknown:
                break
            }
        }
    }

}
