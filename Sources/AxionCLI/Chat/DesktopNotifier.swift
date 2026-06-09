import Foundation

/// 桌面通知发射器 — 受 Codex notifications/ 模块启发。
///
/// 支持两种通知方式：
/// 1. **OSC 9** (`\x1b]9;message\x07`) — 终端桌面通知（iTerm2、Ghostty、Kitty、WezTerm、Warp）
/// 2. **BEL** (`\x07`) — 终端响铃，作为不支持 OSC 9 的终端的后备方案
///
/// 非 TTY 环境自动静默跳过（同 SpinnerRenderer / TerminalTitleRenderer 模式）。
/// 使用纯函数 + DI 模式，无直接 I/O 依赖。
struct DesktopNotifier {
    /// 通知方式
    enum Method: Sendable {
        /// 自动检测：优先 OSC 9，不支持时回退 BEL
        case auto
        /// 强制使用 OSC 9 桌面通知
        case osc9
        /// 强制使用 BEL 响铃
        case bel
    }

    /// 通知事件类型 — 不同事件有不同的优先级和展示需求。
    enum NotificationEvent: Sendable {
        /// Agent turn 完成（含响应预览）
        case agentTurnComplete(preview: String)
        /// 工具需要审批（含工具名）
        case approvalRequested(toolName: String)
        /// 上下文窗口使用率警告
        case contextWarning(pct: Int)
    }

    private let method: Method
    private let isTTY: Bool
    private let writeStderr: (String) -> Void

    /// TERM_PROGRAM 环境变量值（用于 OSC 9 支持检测）
    private let termProgram: String?

    init(
        method: Method = .auto,
        isTTY: Bool = isattty(STDERR_FILENO),
        writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) },
        termProgram: String? = ProcessInfo.processInfo.environment["TERM_PROGRAM"]
    ) {
        self.method = method
        self.isTTY = isTTY
        self.writeStderr = writeStderr
        self.termProgram = termProgram
    }

    // MARK: - Public API

    /// 发送桌面通知。
    ///
    /// 仅在 TTY 环境下生效。根据配置的方式发送 OSC 9 或 BEL。
    /// - Parameter event: 通知事件类型
    func notify(_ event: NotificationEvent) {
        guard isTTY else { return }

        let resolvedMethod = resolveMethod()
        let message = formatMessage(for: event)

        switch resolvedMethod {
        case .osc9:
            writeOSC9(message)
        case .bel:
            writeBEL()
        case .auto:
            break  // already resolved above
        }
    }

    // MARK: - Method Resolution

    /// 解析实际使用的通知方式。
    private func resolveMethod() -> Method {
        switch method {
        case .auto:
            return supportsOSC9() ? .osc9 : .bel
        case .osc9, .bel:
            return method
        }
    }

    /// 检测当前终端是否支持 OSC 9 桌面通知。
    ///
    /// 支持 OSC 9 的终端（与 Codex 一致）：
    /// - Ghostty (`ghostty`)
    /// - iTerm2 (`iTerm.app`)
    /// - Kitty (`kitty`)
    /// - WezTerm (`WezTerm`)
    /// - Warp (`WarpTerminal`)
    static func supportsOSC9(termProgram: String?) -> Bool {
        guard let program = termProgram?.lowercased() else { return false }
        let supported: Set<String> = [
            "ghostty", "iterm.app", "kitty", "wezterm", "warpterminal",
        ]
        return supported.contains(program)
    }

    private func supportsOSC9() -> Bool {
        Self.supportsOSC9(termProgram: termProgram)
    }

    // MARK: - Message Formatting

    /// 格式化通知消息。
    private func formatMessage(for event: NotificationEvent) -> String {
        switch event {
        case .agentTurnComplete(let preview):
            if preview.isEmpty {
                return "Axion: Agent turn complete"
            }
            let truncated = Self.truncatePreview(preview, maxChars: 200)
            return "Axion: \(truncated)"
        case .approvalRequested(let toolName):
            return "Axion: Approval requested for \(toolName)"
        case .contextWarning(let pct):
            return "Axion: ⚠️ Context \(pct)% used"
        }
    }

    /// 截断通知预览文本。
    static func truncatePreview(_ text: String, maxChars: Int = 200) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars - 1)) + "…"
    }

    // MARK: - Output

    /// 发送 OSC 9 桌面通知。
    ///
    /// OSC 9 序列：`\x1b]9;message\x07`
    /// 在 tmux 下需要 DCS passthrough 包装：`\x1bPtmux;\x1b\x1b]9;message\x07\x1b\\`
    private func writeOSC9(_ message: String) {
        let escaped = Self.sanitizeForOSC(message)
        if isTmux() {
            // tmux DCS passthrough
            writeStderr("\u{1B}Ptmux;\u{1B}\u{1B}]9;\(escaped)\u{07}\u{1B}\\")
        } else {
            writeStderr("\u{1B}]9;\(escaped)\u{07}")
        }
    }

    /// 发送 BEL（终端响铃）。
    private func writeBEL() {
        writeStderr("\u{07}")
    }

    /// 检测是否在 tmux 下运行。
    private func isTmux() -> Bool {
        ProcessInfo.processInfo.environment["TMUX"] != nil
    }

    /// 清理 OSC 消息中的特殊字符。
    ///
    /// 移除 BEL（\x07）、ESC（\x1B）等会破坏序列结构的字符。
    static func sanitizeForOSC(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            let val = scalar.value
            // Skip BEL (0x07) and ESC (0x1B) — they break OSC sequences
            if val == 0x07 || val == 0x1B { continue }
            result.append(Character(scalar))
        }
        return result
    }
}

// MARK: - Private TTY helper

/// 可测试的 isatty 包装。
private func isattty(_ fd: Int32) -> Bool {
    isatty(fd) != 0
}
