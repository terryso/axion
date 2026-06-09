import Foundation
import Testing

@testable import AxionCLI

// [P0] 基础设施验证 — TerminalColorProfile 颜色探测和 ANSI 码映射
// TDD RED PHASE: 测试引用尚未实现的 TerminalColorProfile 类型

@Suite("TerminalColorProfile")
struct TerminalColorProfileTests {

    // MARK: - detect() 环境变量探测 (AC7)

    @Test("detect: COLORTERM=truecolor 返回 .trueColor")
    func detect_trueColor() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: "truecolor",
            term: "xterm-256color"
        )
        #expect(profile == .trueColor)
    }

    @Test("detect: COLORTERM=24bit 返回 .trueColor")
    func detect_24bit() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: "24bit",
            term: "xterm-256color"
        )
        #expect(profile == .trueColor)
    }

    @Test("detect: TERM=xterm-256color 返回 .ansi256")
    func detect_ansi256_xterm() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: nil,
            term: "xterm-256color"
        )
        #expect(profile == .ansi256)
    }

    @Test("detect: TERM=screen-256color 返回 .ansi256 (screen 兼容 AC5)")
    func detect_ansi256_screen() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: nil,
            term: "screen-256color"
        )
        #expect(profile == .ansi256)
    }

    @Test("detect: TERM=tmux-256color 返回 .ansi256 (tmux 兼容 AC5)")
    func detect_ansi256_tmux() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: nil,
            term: "tmux-256color"
        )
        #expect(profile == .ansi256)
    }

    @Test("detect: TERM=xterm 返回 .ansi16")
    func detect_ansi16_xterm() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: nil,
            term: "xterm"
        )
        #expect(profile == .ansi16)
    }

    @Test("detect: TERM=vt100 返回 .ansi16")
    func detect_ansi16_vt() {
        let profile = TerminalColorProfile.detect(
            isTTY: true,
            colorterm: nil,
            term: "vt100"
        )
        #expect(profile == .ansi16)
    }

    @Test("detect: 非 TTY (isatty=false) 返回 .unknown (AC4)")
    func detect_nonTTY() {
        let profile = TerminalColorProfile.detect(
            isTTY: false,
            colorterm: "truecolor",
            term: "xterm-256color"
        )
        #expect(profile == .unknown)
    }

    // MARK: - ansiColor(for:) 角色颜色映射 (AC7)

    @Test("trueColor: 蓝色角色返回 24-bit RGB ANSI 码")
    func trueColor_blueRole() {
        let profile = TerminalColorProfile.trueColor
        let color = profile.ansiColor(for: .user)
        // TrueColor 使用 \033[38;2;R;G;Bm 格式
        #expect(color.contains("38;2;"))
        #expect(color.hasSuffix("m"))
    }

    @Test("trueColor: 绿色角色返回 24-bit RGB ANSI 码")
    func trueColor_greenRole() {
        let profile = TerminalColorProfile.trueColor
        let color = profile.ansiColor(for: .assistant)
        #expect(color.contains("38;2;"))
        #expect(color.hasSuffix("m"))
    }

    @Test("trueColor: 黄色角色返回 24-bit RGB ANSI 码")
    func trueColor_yellowRole() {
        let profile = TerminalColorProfile.trueColor
        let color = profile.ansiColor(for: .tool)
        #expect(color.contains("38;2;"))
        #expect(color.hasSuffix("m"))
    }

    @Test("trueColor: 红色角色返回 24-bit RGB ANSI 码")
    func trueColor_redRole() {
        let profile = TerminalColorProfile.trueColor
        let color = profile.ansiColor(for: .warning)
        #expect(color.contains("38;2;"))
        #expect(color.hasSuffix("m"))
    }

    @Test("ansi256: 蓝色角色返回 256 色 ANSI 码")
    func ansi256_blueRole() {
        let profile = TerminalColorProfile.ansi256
        let color = profile.ansiColor(for: .user)
        // Ansi256 使用 \033[38;5;Nm 格式
        #expect(color.contains("38;5;"))
        #expect(color.hasSuffix("m"))
    }

    @Test("ansi256: 各角色返回不同的 ANSI 码")
    func ansi256_uniqueColors() {
        let profile = TerminalColorProfile.ansi256
        let userColor = profile.ansiColor(for: .user)
        let aiColor = profile.ansiColor(for: .assistant)
        let toolColor = profile.ansiColor(for: .tool)
        let warnColor = profile.ansiColor(for: .warning)
        #expect(userColor != aiColor)
        #expect(userColor != toolColor)
        #expect(userColor != warnColor)
        #expect(aiColor != toolColor)
        #expect(aiColor != warnColor)
        #expect(toolColor != warnColor)
    }

    @Test("ansi16: 蓝色角色返回标准 16 色码 34")
    func ansi16_blue() {
        let profile = TerminalColorProfile.ansi16
        let color = profile.ansiColor(for: .user)
        #expect(color == "\u{1B}[34m")
    }

    @Test("ansi16: 绿色角色返回标准 16 色码 32")
    func ansi16_green() {
        let profile = TerminalColorProfile.ansi16
        let color = profile.ansiColor(for: .assistant)
        #expect(color == "\u{1B}[32m")
    }

    @Test("ansi16: 黄色角色返回标准 16 色码 33")
    func ansi16_yellow() {
        let profile = TerminalColorProfile.ansi16
        let color = profile.ansiColor(for: .tool)
        #expect(color == "\u{1B}[33m")
    }

    @Test("ansi16: 红色角色返回标准 16 色码 31")
    func ansi16_red() {
        let profile = TerminalColorProfile.ansi16
        let color = profile.ansiColor(for: .warning)
        #expect(color == "\u{1B}[31m")
    }

    @Test("unknown: 所有角色返回空字符串（无颜色输出）")
    func unknown_noColors() {
        let profile = TerminalColorProfile.unknown
        #expect(profile.ansiColor(for: .user).isEmpty)
        #expect(profile.ansiColor(for: .assistant).isEmpty)
        #expect(profile.ansiColor(for: .tool).isEmpty)
        #expect(profile.ansiColor(for: .warning).isEmpty)
    }
}
