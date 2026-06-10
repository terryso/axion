import Foundation
import OpenAgentSDK
import Testing
import AxionCore

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

    @Test("renderBanner 包含版本号、模型、CWD、sessionId、快捷键提示")
    func renderBanner_containsKeyInfo() {
        let banner = BannerRenderer.renderBanner(
            version: "0.11.0",
            model: "claude-sonnet-4-6",
            cwd: "/Users/nick/project",
            sessionId: "chat-a3f8b2c1",
            contextWindow: 200_000,
            buildTimeMs: 157,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(banner.contains("Axion v0.11.0"))
        #expect(banner.contains("claude-sonnet-4-6"))
        #expect(banner.contains("/Users/nick/project"))
        #expect(banner.contains("chat-a3f8b2c1"))
        #expect(banner.contains("0/200k"))
        #expect(banner.contains("157ms"))
        #expect(banner.contains("/help"))
        // Codex-inspired: 横幅现在包含快捷键提示行
        #expect(banner.contains("[Enter]"))
        #expect(banner.contains("[Ctrl+C]"))
    }

    @Test("renderBanner 秒级耗时格式化")
    func renderBanner_buildTimeSeconds() {
        let banner = BannerRenderer.renderBanner(
            version: "1.0",
            model: "test-model",
            cwd: "/tmp",
            sessionId: "chat-abc12345",
            contextWindow: 200_000,
            buildTimeMs: 2345,
            isTTY: false,
            colorProfile: .unknown
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
            buildTimeMs: 100,
            isTTY: false,
            colorProfile: .unknown
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

    // MARK: - renderPrompt with turnNumber

    @Test("renderPrompt 非 TTY 含回合号显示 T3")
    func renderPrompt_nonTTY_withTurnNumber() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [12k/200k 6% T3]> ")
    }

    @Test("renderPrompt TTY 含回合号显示在进度条后")
    func renderPrompt_tty_withTurnNumber() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 30_000,
            contextWindow: 200_000,
            turnNumber: 5,
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(prompt.contains("T5"))
        #expect(prompt.contains("15%"))
        #expect(prompt.hasSuffix("T5]> "))
    }

    @Test("renderPrompt 回合号为零时不显示回合标签")
    func renderPrompt_zeroTurnNumber() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 0,
            contextWindow: 200_000,
            turnNumber: 0,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(!prompt.contains("T0"))
        #expect(prompt == "axion [0/200k 0%]> ")
    }

    // MARK: - renderPrompt with estimatedCost

    @Test("renderPrompt 非 TTY 含成本显示在回合号后")
    func renderPrompt_nonTTY_withCost() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [12k/200k 6% T3 $0.05]> ")
    }

    @Test("renderPrompt 非 TTY 无成本时不显示成本段")
    func renderPrompt_nonTTY_noCost() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: nil,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [12k/200k 6% T3]> ")
    }

    @Test("renderPrompt TTY 含成本显示带 dim 样式")
    func renderPrompt_tty_withCost() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 30_000,
            contextWindow: 200_000,
            turnNumber: 5,
            estimatedCost: "$0.12",
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(prompt.contains("$0.12"))
        #expect(prompt.contains("T5"))
        #expect(prompt.contains("15%"))
        // Should contain dim color for cost separator
        #expect(prompt.contains("\u{1B}[38;2;148;163;184m"))
        #expect(prompt.hasSuffix("]> "))
    }

    @Test("renderPrompt TTY ANSI256 含成本使用正确色码")
    func renderPrompt_tty_ansi256_withCost() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.01",
            isTTY: true,
            colorProfile: .ansi256
        )
        #expect(prompt.contains("$0.01"))
        // ANSI256 dim color: 145
        #expect(prompt.contains("\u{1B}[38;5;145m"))
    }

    @Test("renderPrompt TTY ANSI16 含成本使用白色")
    func renderPrompt_tty_ansi16_withCost() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 2,
            estimatedCost: "$0.03",
            isTTY: true,
            colorProfile: .ansi16
        )
        #expect(prompt.contains("$0.03"))
        // ANSI16 dim: white
        #expect(prompt.contains("\u{1B}[37m"))
    }

    @Test("renderPrompt TTY 无成本时不包含 dim 色码分隔符")
    func renderPrompt_tty_noCost_noDimSeparator() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: nil,
            isTTY: true,
            colorProfile: .trueColor
        )
        // Should not contain the · separator between turn and cost
        #expect(!prompt.contains("·"))
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

    // MARK: - formatSessionDuration

    @Test("formatSessionDuration: 300ms → \"0.3s\"")
    func formatSessionDuration_subSecond() {
        #expect(BannerRenderer.formatSessionDuration(ms: 300) == "0.3s")
    }

    @Test("formatSessionDuration: 3200ms → \"3.2s\"")
    func formatSessionDuration_seconds() {
        #expect(BannerRenderer.formatSessionDuration(ms: 3_200) == "3.2s")
    }

    @Test("formatSessionDuration: 5000ms → \"5s\"")
    func formatSessionDuration_exactSeconds() {
        #expect(BannerRenderer.formatSessionDuration(ms: 5_000) == "5s")
    }

    @Test("formatSessionDuration: 125000ms → \"2m 05s\"")
    func formatSessionDuration_minutes() {
        #expect(BannerRenderer.formatSessionDuration(ms: 125_000) == "2m 05s")
    }

    @Test("formatSessionDuration: 6543000ms → \"1h 49m 03s\"")
    func formatSessionDuration_hours() {
        #expect(BannerRenderer.formatSessionDuration(ms: 6_543_000) == "1h 49m 03s")
    }

    @Test("formatSessionDuration: 0ms → \"0s\"")
    func formatSessionDuration_zero() {
        #expect(BannerRenderer.formatSessionDuration(ms: 0) == "0s")
    }

    // MARK: - renderExit

    @Test("renderExit 包含 sessionId（截断为 8 字符）和恢复命令")
    func renderExit_containsSessionId() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-a3f8b2c1")
        #expect(exit.contains("chat-a3f"))
        #expect(exit.contains("/resume"))
    }

    @Test("renderExit 以换行结尾")
    func renderExit_endsWithNewline() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-test")
        #expect(exit.hasSuffix("\n"))
    }

    // MARK: - renderExit with session summary

    @Test("renderExit 默认参数仍包含 sessionId 和 /resume")
    func renderExit_defaults_stillContainsSessionId() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-a3f8b2c1")
        #expect(exit.contains("chat-a3f"))
        #expect(exit.contains("/resume"))
    }

    @Test("renderExit 含会话摘要显示时长和回合数")
    func renderExit_withSessionSummary() {
        let usage = TokenUsage(inputTokens: 50_000, outputTokens: 12_000)
        let exit = BannerRenderer.renderExit(
            sessionId: "chat-test1234",
            sessionDurationMs: 125_000,
            turns: 5,
            totalTools: 12,
            usage: usage,
            model: "claude-sonnet-4-6"
        )
        #expect(exit.contains("2m 05s"))
        #expect(exit.contains("5 turns"))
        #expect(exit.contains("12 tools"))
        #expect(exit.contains("↑50k ↓12k"))
        #expect(exit.contains("预估成本"))
    }

    @Test("renderExit 单数形式显示 1 turn 和 1 tool")
    func renderExit_singularForm() {
        let usage = TokenUsage(inputTokens: 3_000, outputTokens: 800)
        let exit = BannerRenderer.renderExit(
            sessionId: "chat-test",
            sessionDurationMs: 5_000,
            turns: 1,
            totalTools: 1,
            usage: usage,
            model: "claude-sonnet-4-6"
        )
        #expect(exit.contains("1 turn"))
        #expect(exit.contains("1 tool"))
    }

    @Test("renderExit 无工具调用时不显示工具计数")
    func renderExit_noTools_omitsToolCount() {
        let usage = TokenUsage(inputTokens: 5_000, outputTokens: 1_000)
        let exit = BannerRenderer.renderExit(
            sessionId: "chat-test",
            sessionDurationMs: 10_000,
            turns: 2,
            totalTools: 0,
            usage: usage,
            model: "claude-sonnet-4-6"
        )
        #expect(!exit.contains("tools"))
        #expect(exit.contains("2 turns"))
    }

    @Test("renderExit opus 模型显示不同成本估算")
    func renderExit_opusModelCost() {
        let usage = TokenUsage(inputTokens: 50_000, outputTokens: 12_000)
        let exitSonnet = BannerRenderer.renderExit(
            sessionId: "chat-test",
            sessionDurationMs: 60_000,
            turns: 3,
            totalTools: 5,
            usage: usage,
            model: "claude-sonnet-4-6"
        )
        let exitOpus = BannerRenderer.renderExit(
            sessionId: "chat-test",
            sessionDurationMs: 60_000,
            turns: 3,
            totalTools: 5,
            usage: usage,
            model: "claude-opus-4-8"
        )
        // Both should have cost lines, opus should be more expensive
        #expect(exitSonnet.contains("预估成本"))
        #expect(exitOpus.contains("预估成本"))
        // Parse costs and compare
        let sonnetCost = exitSonnet.components(separatedBy: "$").last?.trimmingCharacters(in: .whitespacesAndNewlines)
        let opusCost = exitOpus.components(separatedBy: "$").last?.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(sonnetCost != nil)
        #expect(opusCost != nil)
        if let s = sonnetCost, let o = opusCost {
            #expect(Double(s) ?? 0 < Double(o) ?? 0)
        }
    }

    // MARK: - renderPrompt with gitBranch

    @Test("renderPrompt 非 TTY 含 git 分支显示在末尾")
    func renderPrompt_nonTTY_withGitBranch() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [12k/200k 6% T3 $0.05 \u{E0A0}main]> ")
    }

    @Test("renderPrompt 非 TTY 含 dirty 分支（带星号）")
    func renderPrompt_nonTTY_dirtyBranch() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            gitBranch: "feature/auth*",
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [12k/200k 6% T3 \u{E0A0}feature/auth*]> ")
    }

    @Test("renderPrompt 非 TTY 无 git 分支不显示分支段")
    func renderPrompt_nonTTY_noGitBranch() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: nil,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt == "axion [12k/200k 6% T3 $0.05]> ")
    }

    @Test("renderPrompt TTY 含 git 分支带暖色样式")
    func renderPrompt_tty_withGitBranch() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 30_000,
            contextWindow: 200_000,
            turnNumber: 5,
            estimatedCost: "$0.12",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(prompt.contains("main"))
        #expect(prompt.contains("$0.12"))
        #expect(prompt.contains("T5"))
        // Should contain warm sand color for branch
        #expect(prompt.contains("\u{1B}[38;2;180;170;140m"))
        #expect(prompt.hasSuffix("]> "))
    }

    @Test("renderPrompt TTY ANSI256 含 git 分支")
    func renderPrompt_tty_ansi256_withGitBranch() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            gitBranch: "develop",
            isTTY: true,
            colorProfile: .ansi256
        )
        #expect(prompt.contains("develop"))
        // ANSI256 branch color: 180
        #expect(prompt.contains("\u{1B}[38;5;180m"))
    }

    @Test("renderPrompt TTY ANSI16 含 git 分支使用黄色")
    func renderPrompt_tty_ansi16_withGitBranch() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            gitBranch: "fix-bug",
            isTTY: true,
            colorProfile: .ansi16
        )
        #expect(prompt.contains("fix-bug"))
        // ANSI16 branch color: yellow
        #expect(prompt.contains("\u{1B}[33m"))
    }

    @Test("renderPrompt TTY 无 git 分支时不显示分支分隔符")
    func renderPrompt_tty_noGitBranch_noSeparator() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.01",
            gitBranch: nil,
            isTTY: true,
            colorProfile: .trueColor
        )
        // With cost but no branch: cost separator exists but no branch separator
        #expect(prompt.contains("$0.01"))
        // Should end after cost segment, no trailing ·
        #expect(prompt.hasSuffix("]> "))
    }

    // MARK: - renderPrompt with displayConfig

    @Test("displayConfig 全关时仅显示上下文和百分比")
    func renderPrompt_displayConfig_allOff() {
        let config = PromptDisplayConfig(
            progressBar: false,
            turnCount: false,
            cost: false,
            gitBranch: false
        )
        // Use non-TTY for exact string matching (no ANSI codes)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        // Minimal: axion [10k/200k 5%]>
        #expect(!prompt.contains("T3"))
        #expect(!prompt.contains("$0.05"))
        #expect(!prompt.contains("main"))
        #expect(prompt == "axion [10k/200k 5%]> ")
    }

    @Test("displayConfig 全关非 TTY 格式")
    func renderPrompt_displayConfig_allOff_nonTTY() {
        let config = PromptDisplayConfig(
            progressBar: false,
            turnCount: false,
            cost: false,
            gitBranch: false
        )
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(prompt == "axion [10k/200k 5%]> ")
    }

    @Test("displayConfig 关闭进度条但保留其他段")
    func renderPrompt_displayConfig_noProgressBar() {
        let config = PromptDisplayConfig(progressBar: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!prompt.contains("█"))
        #expect(!prompt.contains("░"))
        #expect(prompt.contains("T3"))
        #expect(prompt.contains("$0.05"))
        #expect(prompt.contains("main"))
    }

    @Test("displayConfig 关闭费用段")
    func renderPrompt_displayConfig_noCost() {
        let config = PromptDisplayConfig(cost: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!prompt.contains("$0.05"))
        #expect(prompt.contains("main"))
        #expect(prompt.contains("T1"))
    }

    @Test("displayConfig 关闭 Git 分支段")
    func renderPrompt_displayConfig_noGitBranch() {
        let config = PromptDisplayConfig(gitBranch: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!prompt.contains("main"))
        #expect(prompt.contains("$0.05"))
    }

    @Test("displayConfig 关闭回合号")
    func renderPrompt_displayConfig_noTurnCount() {
        let config = PromptDisplayConfig(turnCount: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 5,
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!prompt.contains("T5"))
        #expect(prompt == "axion [10k/200k 5%]> ")
    }

    @Test("displayConfig 默认值全开 = 向后兼容")
    func renderPrompt_displayConfig_defaultIsAllOn() {
        let config = PromptDisplayConfig()
        #expect(config.showProgress == true)
        #expect(config.showTurn == true)
        #expect(config.showCost == true)
        #expect(config.showBranch == true)
        #expect(config.branchMaxLength == 15)

        // Default config should produce same result as omitting it
        let withConfig = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        let withoutConfig = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(withConfig == withoutConfig)
    }

    @Test("displayConfig 非 TTY 关闭费用和分支")
    func renderPrompt_displayConfig_nonTTY_noCostNoBranch() {
        let config = PromptDisplayConfig(cost: false, gitBranch: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(prompt == "axion [12k/200k 6% T3]> ")
    }
}
