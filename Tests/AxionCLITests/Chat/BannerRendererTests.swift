import Foundation
import Testing

@testable import AxionCLI

@Suite("BannerRenderer")
struct BannerRendererTests {

    // MARK: - formatTokenCount

    @Test("formatTokenCount: 0 → \"0\"")
    func formatTokenCount_zero() {
        #expect(BannerRenderer.formatTokenCount(0) == "0")
    }

    @Test("formatTokenCount: 500 → \"500\"")
    func formatTokenCount_hundreds() {
        #expect(BannerRenderer.formatTokenCount(500) == "500")
    }

    @Test("formatTokenCount: 999 → \"999\"")
    func formatTokenCount_999() {
        #expect(BannerRenderer.formatTokenCount(999) == "999")
    }

    @Test("formatTokenCount: 1000 → \"1k\"")
    func formatTokenCount_exact1k() {
        #expect(BannerRenderer.formatTokenCount(1_000) == "1k")
    }

    @Test("formatTokenCount: 3200 → \"3.2k\"")
    func formatTokenCount_kWithDecimal() {
        #expect(BannerRenderer.formatTokenCount(3_200) == "3.2k")
    }

    @Test("formatTokenCount: 200000 → \"200k\"")
    func formatTokenCount_exact200k() {
        #expect(BannerRenderer.formatTokenCount(200_000) == "200k")
    }

    @Test("formatTokenCount: 999999 → \"1.0m\"")
    func formatTokenCount_999999() {
        #expect(BannerRenderer.formatTokenCount(999_999) == "1.0m")
    }

    @Test("formatTokenCount: 999949 → \"999.9k\" (k/m 边界)")
    func formatTokenCount_kmBoundary() {
        #expect(BannerRenderer.formatTokenCount(999_949) == "999.9k")
    }

    @Test("formatTokenCount: 1000000 → \"1m\"")
    func formatTokenCount_exact1m() {
        #expect(BannerRenderer.formatTokenCount(1_000_000) == "1m")
    }

    @Test("formatTokenCount: 1500000 → \"1.5m\"")
    func formatTokenCount_mWithDecimal() {
        #expect(BannerRenderer.formatTokenCount(1_500_000) == "1.5m")
    }

    // MARK: - renderBanner

    @Test("renderBanner 包含版本号、模型、CWD、sessionId")
    func renderBanner_containsKeyInfo() {
        let banner = BannerRenderer.renderBanner(
            version: "0.11.0",
            model: "claude-sonnet-4-6",
            cwd: "/Users/nick/project",
            sessionId: "chat-a3f8b2c1",
            contextWindow: 200_000,
            buildTimeMs: 157
        )
        #expect(banner.contains("Axion v0.11.0"))
        #expect(banner.contains("claude-sonnet-4-6"))
        #expect(banner.contains("/Users/nick/project"))
        #expect(banner.contains("chat-a3f8b2c1"))
        #expect(banner.contains("0/200k"))
        #expect(banner.contains("157ms"))
        #expect(banner.contains("/help"))
    }

    @Test("renderBanner 秒级耗时格式化")
    func renderBanner_buildTimeSeconds() {
        let banner = BannerRenderer.renderBanner(
            version: "1.0",
            model: "test-model",
            cwd: "/tmp",
            sessionId: "chat-abc12345",
            contextWindow: 200_000,
            buildTimeMs: 2345
        )
        #expect(banner.contains("2.3s"))
    }

    @Test("renderBanner 长路径被截断")
    func renderBanner_longCwdTruncated() {
        let longPath = "/Users/nick/very/deeply/nested/directory/structure/that/exceeds/max/length/limit/for/display"
        let banner = BannerRenderer.renderBanner(
            version: "1.0",
            model: "test",
            cwd: longPath,
            sessionId: "chat-test",
            contextWindow: 200_000,
            buildTimeMs: 100
        )
        // Banner should still render, path should be truncated with "…"
        #expect(banner.contains("…"))
        #expect(!banner.contains(longPath))
    }

    // MARK: - renderPrompt (enhanced with progress bar)

    @Test("renderPrompt 非 TTY 零用量时显示 0/200k 0%")
    func renderPrompt_nonTTY_zeroUsage() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 0,
            contextWindow: 200_000,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [0/200k 0%]> ")
    }

    @Test("renderPrompt 非 TTY 有用量时显示正确格式")
    func renderPrompt_nonTTY_withUsage() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 3_200,
            contextWindow: 200_000,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [3.2k/200k 1%]> ")
    }

    @Test("renderPrompt TTY 包含进度条和颜色码")
    func renderPrompt_tty_containsBar() {
        // 30k/200k = 15%, 15% of 10 blocks = 1.5 → 1 filled block
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 30_000,
            contextWindow: 200_000,
            isTTY: true,
            colorProfile: .trueColor
        )
        // Should contain percentage and progress bar characters
        #expect(prompt.contains("15%"))
        #expect(prompt.contains("█"))
        #expect(prompt.contains("░"))
        // Should contain ANSI color codes for green (<50%)
        #expect(prompt.contains("\u{1B}[38;2;76;175;80m"))
        #expect(prompt.contains("\u{1B}[0m"))
        #expect(prompt.hasSuffix("]> "))
    }

    @Test("renderPrompt TTY 高使用率使用红色")
    func renderPrompt_tty_highUsage_red() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 180_000,
            contextWindow: 200_000,
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(prompt.contains("90%"))
        // Red color for >80%
        #expect(prompt.contains("\u{1B}[38;2;244;67;54m"))
    }

    @Test("renderPrompt TTY 中等使用率使用黄色")
    func renderPrompt_tty_mediumUsage_yellow() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 120_000,
            contextWindow: 200_000,
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(prompt.contains("60%"))
        // Yellow color for 50-80%
        #expect(prompt.contains("\u{1B}[38;2;255;193;7m"))
    }

    @Test("renderPrompt ANSI16 颜色降级")
    func renderPrompt_ansi16_color() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            isTTY: true,
            colorProfile: .ansi16
        )
        // Green ANSI16
        #expect(prompt.contains("\u{1B}[32m"))
    }

    @Test("renderPrompt 上下文窗口为零时百分比也为零")
    func renderPrompt_zeroContextWindow() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 1_000,
            contextWindow: 0,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [1k/0 0%]> ")
    }

    // MARK: - renderContextBar

    @Test("renderContextBar: 0% → 全空")
    func renderContextBar_zero() {
        #expect(BannerRenderer.renderContextBar(pct: 0, width: 10) == "░░░░░░░░░░")
    }

    @Test("renderContextBar: 50% → 一半填充")
    func renderContextBar_half() {
        #expect(BannerRenderer.renderContextBar(pct: 50, width: 10) == "█████░░░░░")
    }

    @Test("renderContextBar: 100% → 全填充")
    func renderContextBar_full() {
        #expect(BannerRenderer.renderContextBar(pct: 100, width: 10) == "██████████")
    }

    @Test("renderContextBar: 超出范围被 clamp")
    func renderContextBar_clamp() {
        #expect(BannerRenderer.renderContextBar(pct: -10, width: 10) == "░░░░░░░░░░")
        #expect(BannerRenderer.renderContextBar(pct: 150, width: 10) == "██████████")
    }

    @Test("renderContextBar: 自定义宽度")
    func renderContextBar_customWidth() {
        #expect(BannerRenderer.renderContextBar(pct: 50, width: 4) == "██░░")
    }

    // MARK: - contextBarColor

    @Test("contextBarColor: <50% 绿色")
    func contextBarColor_green() {
        let color = BannerRenderer.contextBarColor(pct: 10, profile: .trueColor)
        #expect(color == "\u{1B}[38;2;76;175;80m")
    }

    @Test("contextBarColor: 50-80% 黄色")
    func contextBarColor_yellow() {
        let color = BannerRenderer.contextBarColor(pct: 65, profile: .trueColor)
        #expect(color == "\u{1B}[38;2;255;193;7m")
    }

    @Test("contextBarColor: >80% 红色")
    func contextBarColor_red() {
        let color = BannerRenderer.contextBarColor(pct: 90, profile: .trueColor)
        #expect(color == "\u{1B}[38;2;244;67;54m")
    }

    @Test("contextBarColor: unknown profile 无颜色")
    func contextBarColor_unknown() {
        let color = BannerRenderer.contextBarColor(pct: 50, profile: .unknown)
        #expect(color.isEmpty)
    }

    @Test("contextBarColor: 边界值 50% 黄色")
    func contextBarColor_boundary50() {
        let color = BannerRenderer.contextBarColor(pct: 50, profile: .ansi16)
        #expect(color == "\u{1B}[33m")  // yellow
    }

    @Test("contextBarColor: 边界值 80% 红色")
    func contextBarColor_boundary80() {
        let color = BannerRenderer.contextBarColor(pct: 80, profile: .ansi16)
        #expect(color == "\u{1B}[33m")  // yellow (80% still yellow, >80% red)
    }

    @Test("contextBarColor: 边界值 81% 红色")
    func contextBarColor_boundary81() {
        let color = BannerRenderer.contextBarColor(pct: 81, profile: .ansi16)
        #expect(color == "\u{1B}[31m")  // red
    }

    // MARK: - renderExit

    @Test("renderExit 包含 sessionId 和恢复命令")
    func renderExit_containsSessionId() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-a3f8b2c1")
        #expect(exit.contains("chat-a3f8b2c1"))
        #expect(exit.contains("/resume"))
    }

    @Test("renderExit 以换行结尾")
    func renderExit_endsWithNewline() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-test")
        #expect(exit.hasSuffix("\n"))
    }
}
