import Foundation
import Testing

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
}
