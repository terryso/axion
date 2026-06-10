import Foundation
import Testing
import AxionCore

@testable import AxionCLI
import OpenAgentSDK

/// E2E tests for banner and prompt rendering (BannerRenderer pure functions).
///
/// Tests the visual output that users see at REPL startup, during each turn,
/// and at exit. All tests are pure functions — no API key needed.
@Suite("Banner & Prompt E2E")
struct BannerAndPromptE2ETests {

    // MARK: - formatTokenCount

    @Test("formatTokenCount: 0")
    func formatTokenCountZero() {
        #expect(BannerRenderer.formatTokenCount(0) == "0")
    }

    @Test("formatTokenCount: small numbers")
    func formatTokenCountSmall() {
        #expect(BannerRenderer.formatTokenCount(500) == "500")
        #expect(BannerRenderer.formatTokenCount(999) == "999")
    }

    @Test("formatTokenCount: kilo range")
    func formatTokenCountKilo() {
        #expect(BannerRenderer.formatTokenCount(1_000) == "1k")
        #expect(BannerRenderer.formatTokenCount(3_200) == "3.2k")
        #expect(BannerRenderer.formatTokenCount(10_000) == "10k")
        #expect(BannerRenderer.formatTokenCount(200_000) == "200k")
    }

    @Test("formatTokenCount: mega range")
    func formatTokenCountMega() {
        #expect(BannerRenderer.formatTokenCount(1_000_000) == "1m")
        #expect(BannerRenderer.formatTokenCount(1_500_000) == "1.5m")
    }

    // MARK: - renderBanner

    @Test("banner contains version, model, CWD, session, context")
    func bannerContainsAllFields() {
        let banner = BannerRenderer.renderBanner(
            version: "1.0.0",
            model: "claude-sonnet-4-6",
            cwd: "/Users/test/project",
            sessionId: "chat-abc12345",
            contextWindow: 200_000,
            buildTimeMs: 1500,
            isTTY: false
        )

        #expect(banner.contains("Axion v1.0.0"), "Should contain version")
        #expect(banner.contains("claude-sonnet-4-6"), "Should contain model")
        #expect(banner.contains("chat-abc12345"), "Should contain session ID")
        #expect(banner.contains("200k"), "Should contain context window")
        #expect(banner.contains("Context: 0/200k"), "Should show initial context usage")
    }

    @Test("banner truncates long CWD paths")
    func bannerTruncatesLongCWD() {
        let longPath = "/Users/test/very/deeply/nested/directory/structure/that/exceeds/limit"
        let banner = BannerRenderer.renderBanner(
            version: "1.0.0",
            model: "test",
            cwd: longPath,
            sessionId: "chat-test",
            contextWindow: 100_000,
            buildTimeMs: 100,
            isTTY: false
        )
        // Should contain "…" prefix when path > 60 chars
        #expect(banner.contains("…"), "Should truncate long path with …")
    }

    // MARK: - renderPrompt

    @Test("prompt shows context usage and turn count (non-TTY)")
    func promptNonTTY() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            isTTY: false
        )

        #expect(prompt.contains("12k"), "Should show used tokens")
        #expect(prompt.contains("200k"), "Should show max tokens")
        #expect(prompt.contains("6%"), "Should show percentage")
        #expect(prompt.contains("T3"), "Should show turn count")
        #expect(!prompt.contains("\u{1B}["), "Should not contain ANSI codes in non-TTY")
    }

    @Test("prompt shows progress bar (TTY)")
    func promptTTY() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 1,
            isTTY: true,
            colorProfile: .ansi16
        )

        #expect(prompt.contains("░"), "Should show empty progress blocks")
        #expect(prompt.contains("T1"), "Should show turn count")
    }

    @Test("prompt high usage shows filled blocks")
    func promptHighUsage() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 180_000,
            contextWindow: 200_000,
            turnNumber: 12,
            isTTY: true,
            colorProfile: .ansi16
        )

        #expect(prompt.contains("█"), "Should show filled progress blocks")
        #expect(prompt.contains("T12"), "Should show turn count")
    }

    @Test("prompt zero usage shows empty bar")
    func promptZeroUsage() {
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 0,
            contextWindow: 200_000,
            turnNumber: 0,
            isTTY: true,
            colorProfile: .ansi16
        )

        #expect(prompt.contains("0%"), "Should show 0%")
        #expect(!prompt.contains("█"), "Should not show filled blocks at 0%")
    }

    // MARK: - renderContextBar

    @Test("context bar: 0% is all empty")
    func contextBarZero() {
        let bar = BannerRenderer.renderContextBar(pct: 0, width: 10)
        #expect(bar == "░░░░░░░░░░")
    }

    @Test("context bar: 50% is half filled")
    func contextBarFifty() {
        let bar = BannerRenderer.renderContextBar(pct: 50, width: 10)
        #expect(bar == "█████░░░░░")
    }

    @Test("context bar: 100% is all filled")
    func contextBarFull() {
        let bar = BannerRenderer.renderContextBar(pct: 100, width: 10)
        #expect(bar == "██████████")
    }

    // MARK: - contextBarColor

    @Test("color: green for <50%")
    func colorGreen() {
        let color = BannerRenderer.contextBarColor(pct: 30, profile: .ansi16)
        #expect(color == "\u{1B}[32m", "Should be green for low usage")
    }

    @Test("color: yellow for 50-80%")
    func colorYellow() {
        let color = BannerRenderer.contextBarColor(pct: 65, profile: .ansi16)
        #expect(color == "\u{1B}[33m", "Should be yellow for medium usage")
    }

    @Test("color: red for >80%")
    func colorRed() {
        let color = BannerRenderer.contextBarColor(pct: 90, profile: .ansi16)
        #expect(color == "\u{1B}[31m", "Should be red for high usage")
    }

    // MARK: - renderExit

    @Test("exit banner contains session stats")
    func exitBanner() {
        let exit = BannerRenderer.renderExit(
            sessionId: "chat-abc12345",
            sessionDurationMs: 65_000,
            turns: 5,
            totalTools: 8,
            usage: TokenUsage(inputTokens: 12_000, outputTokens: 3_500),
            model: "claude-sonnet-4-6"
        )

        #expect(exit.contains("chat-abc"), "Should contain session ID prefix")
        #expect(exit.contains("5 turns"), "Should show turn count")
        #expect(exit.contains("8 tools"), "Should show tool count")
        #expect(exit.contains("12k"), "Should show input tokens")
        #expect(exit.contains("3.5k"), "Should show output tokens")
        #expect(exit.contains("预估成本"), "Should show estimated cost")
    }

    @Test("exit banner without tools omits tool count")
    func exitBannerNoTools() {
        let exit = BannerRenderer.renderExit(
            sessionId: "chat-test",
            sessionDurationMs: 3_000,
            turns: 1,
            totalTools: 0,
            usage: nil,
            model: ""
        )

        #expect(!exit.contains("tools"), "Should not show tools when 0")
        #expect(exit.contains("1 turn"), "Should show turn count")
    }

    // MARK: - renderResumeBanner

    @Test("resume banner contains session info")
    func resumeBanner() {
        let banner = BannerRenderer.renderResumeBanner(
            sessionId: "chat-resume123",
            messageCount: 15,
            model: "claude-sonnet-4-6",
            contextWindow: 200_000,
            isTTY: false
        )

        #expect(banner.contains("chat-resume123"), "Should contain session ID")
        #expect(banner.contains("15"), "Should contain message count")
        #expect(banner.contains("claude-sonnet-4-6"), "Should contain model")
        #expect(banner.contains("200k"), "Should contain context window")
    }

    // MARK: - formatSessionDuration

    @Test("session duration: seconds")
    func sessionDurationSeconds() {
        let dur = BannerRenderer.formatSessionDuration(ms: 3_200)
        #expect(dur == "3.2s")
    }

    @Test("session duration: minutes and seconds")
    func sessionDurationMinutes() {
        let dur = BannerRenderer.formatSessionDuration(ms: 125_000)
        #expect(dur == "2m 05s")
    }

    @Test("session duration: hours")
    func sessionDurationHours() {
        let dur = BannerRenderer.formatSessionDuration(ms: 3_753_000)
        #expect(dur == "1h 02m 33s")
    }

    // MARK: - displayConfig E2E

    @Test("E2E: displayConfig 全关 → prompt 仅含上下文和百分比")
    func e2e_displayConfig_allOff() {
        let config = PromptDisplayConfig(
            progressBar: false,
            turnCount: false,
            cost: false,
            gitBranch: false
        )
        // TTY mode
        let ttyPrompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .ansi16,
            displayConfig: config
        )
        #expect(ttyPrompt.contains("12k"))
        #expect(ttyPrompt.contains("200k"))
        #expect(ttyPrompt.contains("6%"))
        #expect(!ttyPrompt.contains("T3"), "Turn should be hidden")
        #expect(!ttyPrompt.contains("$0.05"), "Cost should be hidden")
        #expect(!ttyPrompt.contains("main"), "Branch should be hidden")
        #expect(!ttyPrompt.contains("█"), "Progress bar should be hidden")
        #expect(!ttyPrompt.contains("░"), "Progress bar should be hidden")

        // Non-TTY mode
        let plainPrompt = BannerRenderer.renderPrompt(
            usedTokens: 12_000,
            contextWindow: 200_000,
            turnNumber: 3,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(plainPrompt == "axion [12k/200k 6%]> ")
    }

    @Test("E2E: displayConfig 关进度条 → TTY 无 ░/█ 但保留其他段")
    func e2e_displayConfig_noProgressBar() {
        let config = PromptDisplayConfig(progressBar: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 30_000,
            contextWindow: 200_000,
            turnNumber: 5,
            estimatedCost: "$0.12",
            gitBranch: "develop",
            isTTY: true,
            colorProfile: .trueColor,
            displayConfig: config
        )
        #expect(!prompt.contains("█"), "No filled blocks")
        #expect(!prompt.contains("░"), "No empty blocks")
        #expect(prompt.contains("T5"), "Turn still visible")
        #expect(prompt.contains("$0.12"), "Cost still visible")
        #expect(prompt.contains("develop"), "Branch still visible")
        #expect(prompt.contains("15%"), "Percentage still visible")
    }

    @Test("E2E: displayConfig 关费用 → prompt 无 $ 符号和金额")
    func e2e_displayConfig_noCost() {
        let config = PromptDisplayConfig(cost: false)
        // TTY
        let ttyPrompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.99",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .trueColor,
            displayConfig: config
        )
        #expect(!ttyPrompt.contains("$0.99"), "Cost should be hidden in TTY")
        #expect(ttyPrompt.contains("main"), "Branch still visible")

        // Non-TTY
        let plainPrompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.99",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!plainPrompt.contains("$"), "No dollar sign in non-TTY")
        #expect(plainPrompt.contains("T1"), "Turn still visible")
        #expect(plainPrompt.contains("\u{E0A0}main"), "Branch still visible")
    }

    @Test("E2E: displayConfig 关分支 → prompt 无分支名")
    func e2e_displayConfig_noGitBranch() {
        let config = PromptDisplayConfig(gitBranch: false)
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 2,
            estimatedCost: "$0.05",
            gitBranch: "feature/auth",
            isTTY: true,
            colorProfile: .ansi16,
            displayConfig: config
        )
        #expect(!prompt.contains("feature/auth"), "Branch should be hidden")
        #expect(!prompt.contains("auth"), "No branch substring")
        #expect(prompt.contains("$0.05"), "Cost still visible")
        #expect(prompt.contains("T2"), "Turn still visible")
    }

    @Test("E2E: displayConfig 关回合号 → prompt 无 T 标签")
    func e2e_displayConfig_noTurnCount() {
        let config = PromptDisplayConfig(turnCount: false)
        // TTY
        let ttyPrompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 42,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: true,
            colorProfile: .trueColor,
            displayConfig: config
        )
        #expect(!ttyPrompt.contains("T42"), "Turn label should be hidden in TTY")
        #expect(ttyPrompt.contains("main"), "Branch still visible")

        // Non-TTY
        let plainPrompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 42,
            estimatedCost: "$0.05",
            gitBranch: "main",
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!plainPrompt.contains("T42"), "Turn label hidden in non-TTY")
        #expect(plainPrompt == "axion [10k/200k 5% $0.05 \u{E0A0}main]> ")
    }

    @Test("E2E: displayConfig 默认值 → 与不传 config 完全一致（向后兼容）")
    func e2e_displayConfig_default_backwardCompat() {
        let defaultConfig = PromptDisplayConfig()
        let args: (Int, Int, Int, String?, String?, Bool, TerminalColorProfile) = (
            12_000, 200_000, 3, "$0.05", "main", false, TerminalColorProfile.unknown
        )
        let withConfig = BannerRenderer.renderPrompt(
            usedTokens: args.0,
            contextWindow: args.1,
            turnNumber: args.2,
            estimatedCost: args.3,
            gitBranch: args.4,
            isTTY: args.5,
            colorProfile: args.6,
            displayConfig: defaultConfig
        )
        let withoutConfig = BannerRenderer.renderPrompt(
            usedTokens: args.0,
            contextWindow: args.1,
            turnNumber: args.2,
            estimatedCost: args.3,
            gitBranch: args.4,
            isTTY: args.5,
            colorProfile: args.6
        )
        #expect(withConfig == withoutConfig, "Default config must be backward compatible")
    }

    @Test("E2E: displayConfig 部分开关组合（关费用+关分支）")
    func e2e_displayConfig_partialCombo() {
        let config = PromptDisplayConfig(cost: false, gitBranch: false)
        // Non-TTY: axion [12k/200k 6% T3]>
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

    // MARK: - Branch truncation E2E

    @Test("E2E: GitStatus.displayString → renderPrompt 串联截断长分支名")
    func e2e_longBranch_truncationPipeline() {
        let longBranch = "gnhf/cascadeprojects-code-6ba7a0-1"
        let config = PromptDisplayConfig()  // default maxLength = 15

        // 1. GitStatus 截断（模拟 ChatCommand 中的调用链）
        let status = GitBranchDetector.GitStatus(branch: longBranch, isDirty: false)
        let displayBranch = status.displayString(maxLength: config.branchMaxLength)

        // 2. 截断后的分支名传给 renderPrompt
        #expect(!displayBranch.contains(longBranch), "Full branch name should be truncated")
        #expect(displayBranch.hasSuffix("…"), "Should end with truncation indicator")
        #expect(displayBranch.count == 15, "Should be exactly maxLength chars")

        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.05",
            gitBranch: displayBranch,
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        // 3. Prompt 中不包含完整分支名，但包含截断版本
        #expect(!prompt.contains(longBranch), "Full branch name should not appear")
        #expect(prompt.contains("…"), "Should contain truncation indicator")
    }

    @Test("E2E: displayConfig 自定义 branchMaxLength 截断更短")
    func e2e_displayConfig_customBranchMaxLength() {
        let config = PromptDisplayConfig(maxBranchLength: 8)
        #expect(config.branchMaxLength == 8)

        let longBranch = "feature/very-long-branch-name"
        let status = GitBranchDetector.GitStatus(branch: longBranch, isDirty: false)
        let displayBranch = status.displayString(maxLength: config.branchMaxLength)

        // 截断为 prefix(7) + "…" = 8 chars
        #expect(!displayBranch.contains(longBranch), "Full branch name should be truncated")
        #expect(displayBranch.hasSuffix("…"))
        #expect(displayBranch.count == 8, "Should be exactly maxLength=8 chars")

        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            estimatedCost: "$0.05",
            gitBranch: displayBranch,
            isTTY: false,
            colorProfile: .unknown,
            displayConfig: config
        )
        #expect(!prompt.contains(longBranch), "Full branch name should not appear in prompt")
        #expect(prompt.contains("…"), "Should contain truncation indicator in prompt")
    }

    @Test("E2E: GitStatus.displayString 截断 + dirty 星号")
    func e2e_gitStatus_truncation_dirty() {
        let longBranch = "gnhf/cascadeprojects-code-6ba7a0-1"
        let status = GitBranchDetector.GitStatus(branch: longBranch, isDirty: true)
        let display = status.displayString(maxLength: 15)

        #expect(display.hasSuffix("…*"), "Truncated branch + dirty star")
        #expect(display.count == 16, "15 chars branch + 1 star")
        #expect(!display.contains(longBranch), "Full branch not present")

        // Verify it renders correctly in prompt
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            gitBranch: display,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt.contains("…*"), "Prompt shows truncated dirty branch")
    }

    @Test("E2E: GitStatus.displayString 短分支不截断")
    func e2e_gitStatus_shortBranch_noTruncation() {
        let status = GitBranchDetector.GitStatus(branch: "main", isDirty: false)
        let display = status.displayString(maxLength: 15)
        #expect(display == "main")

        // Verify in prompt
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 10_000,
            contextWindow: 200_000,
            turnNumber: 1,
            gitBranch: display,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(prompt.contains("\u{E0A0}main"))
    }

    // MARK: - Config → PromptDisplayConfig 串联 E2E

    @Test("E2E: PromptDisplayConfig 默认属性值正确")
    func e2e_promptDisplayConfig_defaults() {
        let config = PromptDisplayConfig()
        #expect(config.showProgress == true)
        #expect(config.showTurn == true)
        #expect(config.showCost == true)
        #expect(config.showBranch == true)
        #expect(config.branchMaxLength == 15)
    }

    @Test("E2E: PromptDisplayConfig 显式 false 覆盖默认")
    func e2e_promptDisplayConfig_explicitFalse() {
        let config = PromptDisplayConfig(progressBar: false, turnCount: false, cost: false, gitBranch: false)
        #expect(config.showProgress == false)
        #expect(config.showTurn == false)
        #expect(config.showCost == false)
        #expect(config.showBranch == false)
    }

    @Test("E2E: displayConfig 关进度条+关分支 → 非 TTY 无额外段")
    func e2e_displayConfig_noProgressNoBranch_nonTTY() {
        let config = PromptDisplayConfig(progressBar: false, gitBranch: false)
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
        // Non-TTY: no progress bar visible anyway, branch hidden
        #expect(!prompt.contains("main"), "Branch hidden")
        #expect(prompt.contains("$0.05"), "Cost still shown")
        #expect(prompt.contains("T3"), "Turn still shown")
    }

    @Test("E2E: displayConfig 全关 TTY 模式仍可解析为有效 prompt")
    func e2e_displayConfig_allOff_tty_validPrompt() {
        let config = PromptDisplayConfig(
            progressBar: false,
            turnCount: false,
            cost: false,
            gitBranch: false
        )
        let prompt = BannerRenderer.renderPrompt(
            usedTokens: 50_000,
            contextWindow: 200_000,
            turnNumber: 10,
            estimatedCost: "$1.23",
            gitBranch: "develop",
            isTTY: true,
            colorProfile: .trueColor,
            displayConfig: config
        )
        // Must still be a valid prompt
        #expect(prompt.hasPrefix("axion ["))
        #expect(prompt.hasSuffix("]> "))
        #expect(prompt.contains("25%"), "Percentage always visible")
        // Nothing else
        #expect(!prompt.contains("T10"))
        #expect(!prompt.contains("$1.23"))
        #expect(!prompt.contains("develop"))
        #expect(!prompt.contains("█"))
    }
}
