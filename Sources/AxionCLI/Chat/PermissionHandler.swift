import Darwin
import Foundation
import OpenAgentSDK

/// Handles tool permission checks for the interactive chat REPL.
///
/// Provides a ``CanUseToolFn`` closure that:
/// - Auto-allows read-only tools (Read, Grep, Glob, etc.)
/// - Auto-allows Write/Edit in acceptEdits mode
/// - Auto-allows all tools in bypassPermissions mode
/// - Checks session allow list for previously approved commands (v2)
/// - Prompts the user with dynamic approval options (v2)
/// - Denies all non-read-only tools in non-TTY environments (safe default)
enum PermissionHandler {

    // MARK: - Public API

    /// Creates a ``CanUseToolFn`` closure for SDK tool permission checks (v1 — backward compatible).
    ///
    /// - Parameters:
    ///   - mode: The effective permission mode for this session.
    ///   - isTTY: Whether stdin is connected to a TTY (defaults to real `isatty` check).
    ///   - readUserInput: Closure to read a line of user input (injectable for testing).
    /// - Returns: A ``CanUseToolFn`` closure suitable for ``AgentOptions/canUseTool``.
    static func createCanUseTool(
        mode: PermissionMode,
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        readUserInput: @Sendable @escaping () -> String? = { readLine(strippingNewline: true) }
    ) -> CanUseToolFn {
        // AC1–AC4/AC6/AC8: v2 overload without session allow list
        return createCanUseTool(
            mode: mode,
            isTTY: isTTY,
            sessionAllowList: nil,
            escListenerRef: nil,
            readUserInput: readUserInput
        )
    }

    /// Creates a ``CanUseToolFn`` closure with session allow list support (v2).
    ///
    /// When `sessionAllowList` is provided, the closure checks it before prompting.
    /// User decisions (session/prefix) update the shared allow list.
    ///
    /// - Parameters:
    ///   - mode: The effective permission mode for this session.
    ///   - isTTY: Whether stdin is connected to a TTY.
    ///   - sessionAllowList: Shared session allow list reference (nil = v1 behavior).
    ///   - escListenerRef: ESC listener reference for stdin coordination (nil = no coordination).
    ///   - readUserInput: Closure to read a line of user input (injectable for testing).
    /// - Returns: A ``CanUseToolFn`` closure suitable for ``AgentOptions/canUseTool``.
    static func createCanUseTool(
        mode: PermissionMode,
        isTTY: Bool = isatty(STDIN_FILENO) != 0,
        sessionAllowList: SessionAllowListRef?,
        escListenerRef: EscapeInterruptListenerRef? = nil,
        readUserInput: @Sendable @escaping () -> String? = { readLine(strippingNewline: true) }
    ) -> CanUseToolFn {
        // 当有 ESC listener 协调时，使用单字符 raw mode 读取（ESC 立即响应）
        let effectiveReadUserInput: @Sendable () -> String?
        if escListenerRef != nil {
            effectiveReadUserInput = Self.readSingleKey
        } else {
            effectiveReadUserInput = readUserInput
        }

        return { tool, input, _ in
            // AC4: Read-only tools auto-allow in all modes
            if tool.isReadOnly {
                return .allow()
            }

            // AC3: bypassPermissions — auto-allow everything
            if mode == .bypassPermissions {
                return .allow()
            }

            // AC2: acceptEdits — auto-allow Write/Edit, others need confirmation
            if mode == .acceptEdits {
                if tool.name == "Write" || tool.name == "Edit" {
                    return .allow()
                }
                // Fall through to prompt for Bash etc.
            }

            // AC3: Session allow list check (v2 — Story 38.3)
            if let allowList = sessionAllowList {
                let commandKey = extractCommandKey(tool: tool, input: input)
                if let key = commandKey, allowList.isAllowed(command: key) {
                    return .allow()  // Already approved in this session
                }
            }

            // AC8: non-TTY safety — deny (cannot interact)
            if !isTTY {
                return .deny("非终端环境，拒绝执行 \(tool.name)")
            }

            // ── 即将渲染提示 + 读取用户输入 ──
            // 先暂停 ESC 监听器：停止其 stdin 轮询 + 恢复 canonical mode，
            // 确保渲染提示后用户输入不会被 ESC listener 吞掉。
            let paused = escListenerRef?.pause() ?? false
            defer {
                if paused { escListenerRef?.resume() }
            }

            // v2: dynamic approval options
            if let allowList = sessionAllowList {
                return handleV2Approval(
                    tool: tool,
                    input: input,
                    allowList: allowList,
                    readUserInput: effectiveReadUserInput
                )
            }

            // v1: original [y/n] prompt (backward compatible)
            return handleV1Prompt(
                tool: tool,
                input: input,
                readUserInput: effectiveReadUserInput
            )
        }
    }

    // MARK: - Single-Key Input

    /// 读取单个按键 — 用于权限提示，ESC (0x1B) 立即响应，无需按 Enter。
    ///
    /// 流程：
    /// 1. 保存当前 termios（由 `pause()` 恢复的 canonical mode）
    /// 2. 切换到 raw mode（ICANON off, VMIN=1, VTIME=0）
    /// 3. 读取一个字节
    /// 4. 刷新残余输入（如用户输入了 'a' + Enter）
    /// 5. 恢复 termios
    ///
    /// 对于测试环境（非 TTY），降级到 `readLine()`。
    static func readSingleKey() -> String? {
        // 非 TTY 降级
        guard isatty(STDIN_FILENO) != 0 else {
            return readLine(strippingNewline: true)
        }

        // 保存当前 termios
        var orig = termios()
        guard tcgetattr(STDIN_FILENO, &orig) == 0 else {
            return readLine(strippingNewline: true)
        }

        // 切换到最小 raw mode：关 echo、关 canonical、阻塞读 1 字节
        var raw = orig
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        raw.c_cc.16 = 1  // VMIN = 1（阻塞等 1 字节）
        raw.c_cc.17 = 0  // VTIME = 0（无超时）
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)

        // 读取一个字节
        var byte: UInt8 = 0
        let bytesRead = read(STDIN_FILENO, &byte, 1)

        // 刷新残余输入（用户可能多输入了字符/Enter）
        tcflush(STDIN_FILENO, TCIFLUSH)

        // 恢复 termios
        var restore = orig
        tcsetattr(STDIN_FILENO, TCSANOW, &restore)

        guard bytesRead == 1 else { return nil }

        // ESC (0x1B) 或其他控制字符 → 统一当拒绝（nil → decline）
        if byte < 0x20 || byte == 0x7F { return nil }

        // ASCII 可打印字符
        if byte < 0x80 {
            return String(UnicodeScalar(byte))
        }

        // UTF-8 多字节字符（CJK 等）
        let len = KeyEventReader.utf8CharLength(byte)
        var bytes = [byte]
        // 注意：残余 UTF-8 字节已被 tcflush 清掉，这里是尽力而为
        for _ in 1..<len {
            var b: UInt8 = 0
            if read(STDIN_FILENO, &b, 1) == 1 { bytes.append(b) }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    // MARK: - Mode Resolution

    /// Computes the effective ``PermissionMode`` from CLI flags.
    static func resolveMode(
        acceptEdits: Bool,
        dangerouslySkipPermissions: Bool
    ) -> PermissionMode {
        if dangerouslySkipPermissions {
            return .bypassPermissions
        }
        if acceptEdits {
            return .acceptEdits
        }
        return .default
    }

    /// Returns a human-readable display name for the permission mode (used in /config).
    static func modeDisplayName(_ mode: PermissionMode) -> String {
        switch mode {
        case .default: return "default"
        case .acceptEdits: return "acceptEdits"
        case .bypassPermissions: return "bypassPermissions"
        case .plan: return "plan"
        case .dontAsk: return "dontAsk"
        case .auto: return "auto"
        }
    }
}
