import Foundation

/// 终端颜色能力探测 — AC7: 颜色降级链
///
/// 通过环境变量探测终端颜色支持级别，不使用 OSC 背景色查询（tmux/screen 不可靠）。
/// 所有视觉输出组件通过此 profile 决定使用哪种 ANSI 颜色方案。
///
/// - trueColor: 24-bit RGB (`\033[38;2;R;G;Bm`)
/// - ansi256: 216 色立方体 (`\033[38;5;Nm`)
/// - ansi16: 标准 16 色 (`\033[3Xm`)
/// - unknown: 无颜色输出（pipe 模式、非 TTY）
enum TerminalColorProfile: String, Sendable, Equatable {
    case trueColor
    case ansi256
    case ansi16
    case unknown

    // MARK: - 探测

    /// 探测终端颜色能力（纯函数，参数化便于测试）。
    /// - Parameters:
    ///   - isTTY: `isatty()` 结果（生产环境通过系统调用获取）
    ///   - colorterm: `COLORTERM` 环境变量值
    ///   - term: `TERM` 环境变量值
    /// - Returns: 检测到的颜色 profile
    static func detect(
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        colorterm: String? = ProcessInfo.processInfo.environment["COLORTERM"],
        term: String = ProcessInfo.processInfo.environment["TERM"] ?? ""
    ) -> TerminalColorProfile {
        // AC4: 非 TTY 直接回退 unknown
        guard isTTY else { return .unknown }

        // COLORTERM=truecolor|24bit → TrueColor
        if let ct = colorterm, ct == "truecolor" || ct == "24bit" {
            return .trueColor
        }

        // TERM *-256color → Ansi256
        if term.hasPrefix("xterm-256color")
            || term.hasPrefix("screen-256color")
            || term.hasPrefix("tmux-256color") {
            return .ansi256
        }

        // 已知的基本终端类型 → Ansi16
        if term.hasPrefix("xterm") || term.hasPrefix("vt") || term.hasPrefix("linux") {
            return .ansi16
        }

        // 默认安全回退
        return .ansi16
    }

    // MARK: - 角色颜色映射

    /// 返回指定语义角色在本 profile 下的 ANSI 前景色码。
    /// - Parameter role: 语义角色（user/assistant/tool/warning）
    /// - Returns: ANSI 转义序列字符串（unknown profile 返回空字符串）
    func ansiColor(for role: TranscriptRole) -> String {
        switch self {
        case .trueColor:
            return trueColorANSI(for: role)
        case .ansi256:
            return ansi256ANSI(for: role)
        case .ansi16:
            return ansi16ANSI(for: role)
        case .unknown:
            return ""  // AC4: 无颜色输出
        }
    }

    // MARK: - TrueColor (24-bit RGB)

    /// 语义角色到精确 RGB 色的映射
    private func trueColorANSI(for role: TranscriptRole) -> String {
        let rgb: (r: Int, g: Int, b: Int)
        switch role {
        case .user:       rgb = (68, 138, 255)    // 明亮蓝
        case .assistant:  rgb = (76, 175, 80)     // 明亮绿
        case .tool:       rgb = (255, 193, 7)     // 明亮黄
        case .warning:    rgb = (244, 67, 54)     // 明亮红
        }
        return "\u{1B}[38;2;\(rgb.r);\(rgb.g);\(rgb.b)m"
    }

    // MARK: - Ansi256 (216 色立方体)

    /// 将 RGB 映射到最近的 216 色立方体索引 (16 + 36*r + 6*g + b)
    private func ansi256ANSI(for role: TranscriptRole) -> String {
        let rgb: (r: Double, g: Double, b: Double)
        switch role {
        case .user:       rgb = (68.0/255, 138.0/255, 255.0/255)
        case .assistant:  rgb = (76.0/255, 175.0/255, 80.0/255)
        case .tool:       rgb = (255.0/255, 193.0/255, 7.0/255)
        case .warning:    rgb = (244.0/255, 67.0/255, 54.0/255)
        }
        let idx = 16 + 36 * nearestCube(rgb.r) + 6 * nearestCube(rgb.g) + nearestCube(rgb.b)
        return "\u{1B}[38;5;\(idx)m"
    }

    /// 将 [0,1] 映射到 6 级色阶 (0-5)
    private func nearestCube(_ component: Double) -> Int {
        let scaled = component * 5.0
        return max(0, min(5, Int(scaled.rounded())))
    }

    // MARK: - Ansi16 (标准 16 色)

    /// 语义角色到标准 16 色码的映射
    private func ansi16ANSI(for role: TranscriptRole) -> String {
        switch role {
        case .user:       return "\u{1B}[34m"   // blue
        case .assistant:  return "\u{1B}[32m"   // green
        case .tool:       return "\u{1B}[33m"   // yellow
        case .warning:    return "\u{1B}[31m"   // red
        }
    }
}
