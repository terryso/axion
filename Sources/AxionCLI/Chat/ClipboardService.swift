import Foundation

/// macOS 剪贴板服务 — 将文本复制到系统剪贴板。
///
/// Codex-inspired (clipboard_copy.rs): 提供 `/copy` 命令底层实现，
/// 支持多种剪贴板后端自动降级。
///
/// 降级链（macOS 优先）：
/// 1. `pbcopy`（macOS 原生）— 本地会话首选
/// 2. OSC 52 转义序列 — SSH/tmux 会话首选，或 pbcopy 不可用时降级
/// 3. tmux 穿透 — tmux 内会话包装 OSC 52 为 DCS passthrough
///
/// 设计原则：
/// - 纯函数 + 注入闭包，无直接 I/O
/// - 所有方法为 `static`，不持有状态
/// - 闭包参数使测试无需真实剪贴板
struct ClipboardService: Sendable {

    // MARK: - Types

    /// 剪贴板操作结果
    enum CopyResult: Equatable, Sendable {
        case success(backend: String)  // backend: "pbcopy" | "osc52" | "tmux"
        case failure(String)           // 错误描述
    }

    /// 环境检测上下文（纯数据，注入式便于测试）
    struct Environment: Equatable, Sendable {
        let isSSHSession: Bool
        let isTmuxSession: Bool

        static func detect(
            env: [String: String] = ProcessInfo.processInfo.environment
        ) -> Environment {
            let isSSH = env["SSH_TTY"] != nil || env["SSH_CONNECTION"] != nil
            let isTmux = env["TMUX"] != nil || env["TMUX_PANE"] != nil
            return Environment(isSSHSession: isSSH, isTmuxSession: isTmux)
        }
    }

    // MARK: - Public API

    /// 将文本复制到系统剪贴板。
    ///
    /// 根据当前环境自动选择最佳剪贴板后端：
    /// - SSH 会话：优先使用 OSC 52（将文本发送到本地终端剪贴板）
    /// - 本地会话：优先使用 `pbcopy`，失败时降级到 OSC 52
    ///
    /// - Parameters:
    ///   - text: 要复制的文本
    ///   - env: 环境检测上下文（默认自动检测）
    ///   - pbcopyFn: pbcopy 执行闭包（默认调用 Process）
    ///   - osc52Fn: OSC 52 写入闭包（默认写入 stderr）
    ///   - tmuxFn: tmux 剪贴板闭包（默认调用 tmux load-buffer）
    /// - Returns: 复制结果
    static func copy(
        text: String,
        env: Environment = .detect(),
        pbcopyFn: (String) -> Bool = defaultPbcopy,
        osc52Fn: (String) -> Bool = defaultOSC52,
        tmuxFn: (String) -> Bool = defaultTmuxCopy
    ) -> CopyResult {
        guard !text.isEmpty else {
            return .failure("没有可复制的内容")
        }

        if env.isSSHSession {
            // SSH 会话：本地剪贴板在远程机器上无用，使用终端中继
            return terminalCopy(
                text: text,
                isTmux: env.isTmuxSession,
                tmuxFn: tmuxFn,
                osc52Fn: osc52Fn
            )
        }

        // 本地会话：优先 pbcopy
        if pbcopyFn(text) {
            return .success(backend: "pbcopy")
        }

        // pbcopy 失败，降级到终端剪贴板
        return terminalCopy(
            text: text,
            isTmux: env.isTmuxSession,
            tmuxFn: tmuxFn,
            osc52Fn: osc52Fn
        )
    }

    // MARK: - Terminal-mediated Copy

    /// 通过终端剪贴板机制复制（OSC 52 或 tmux）。
    private static func terminalCopy(
        text: String,
        isTmux: Bool,
        tmuxFn: (String) -> Bool,
        osc52Fn: (String) -> Bool
    ) -> CopyResult {
        if isTmux {
            // tmux 内：优先使用 tmux 原生剪贴板
            if tmuxFn(text) {
                return .success(backend: "tmux")
            }
            // tmux 失败，降级到 OSC 52（带 DCS passthrough）
            if osc52Fn(text) {
                return .success(backend: "osc52")
            }
            return .failure("tmux 和 OSC 52 剪贴板均不可用")
        }

        // 非 tmux：直接使用 OSC 52
        if osc52Fn(text) {
            return .success(backend: "osc52")
        }
        return .failure("OSC 52 剪贴板不可用（终端可能不支持）")
    }

    // MARK: - Default Implementations

    /// 默认 pbcopy 实现：通过 Process 调用 macOS 原生 pbcopy。
    static func defaultPbcopy(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe

        guard let data = text.data(using: .utf8) else { return false }

        do {
            try process.run()
            pipe.fileHandleForWriting.write(data)
            try pipe.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 默认 OSC 52 实现：写入 stderr（避免干扰 stdout 的 TUI 输出）。
    static func defaultOSC52(_ text: String) -> Bool {
        let isTmux = ProcessInfo.processInfo.environment["TMUX"] != nil
        guard let sequence = osc52Sequence(text: text, isTmux: isTmux) else {
            return false
        }
        // 写入 stderr — Chat 模式的状态信息输出通道
        fputs(sequence, stderr)
        fflush(stderr)
        return true
    }

    /// 默认 tmux 剪贴板实现：通过 tmux load-buffer -w 复制。
    static func defaultTmuxCopy(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "load-buffer", "-w", "-"]
        let pipe = Pipe()
        process.standardInput = pipe

        guard let data = text.data(using: .utf8) else { return false }

        do {
            try process.run()
            pipe.fileHandleForWriting.write(data)
            try pipe.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - OSC 52 Sequence

    /// OSC 52 载荷大小上限（字节）
    static let osc52MaxBytes = 100_000

    /// 生成 OSC 52 剪贴板转义序列。
    ///
    /// - Parameters:
    ///   - text: 要编码的文本
    ///   - isTmux: 是否在 tmux 内（需要 DCS passthrough 包装）
    /// - Returns: OSC 52 转义序列，文本过大时返回 nil
    static func osc52Sequence(text: String, isTmux: Bool) -> String? {
        let rawBytes = text.utf8.count
        guard rawBytes <= osc52MaxBytes else { return nil }

        let encoded = Data(text.utf8).base64EncodedString()

        if isTmux {
            // tmux DCS passthrough: \ePtmux;\e\e]52;c;BASE64\a\e\\
            return "\u{1B}Ptmux;\u{1B}\u{1B}]52;c;\(encoded)\u{07}\u{1B}\\"
        } else {
            // 标准 OSC 52: \e]52;c;BASE64\a
            return "\u{1B}]52;c;\(encoded)\u{07}"
        }
    }

    // MARK: - Format Helpers

    /// 格式化复制成功消息。
    static func formatSuccess(backend: String, charCount: Int) -> String {
        return "[axion] 📋 已复制到剪贴板（\(charCount) 字符，使用 \(backend)）\n"
    }

    /// 格式化复制失败消息。
    static func formatFailure(_ error: String) -> String {
        return "[axion] ❌ 复制失败: \(error)\n"
    }

    /// 格式化无内容可复制消息。
    static func formatNoContent() -> String {
        return "[axion] 没有可复制的内容（尚未收到 assistant 响应）\n"
    }
}
