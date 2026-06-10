import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("SlashCommand /status (AC5)")
struct SlashCommandStatusTests {

    // MARK: - StatusDashboardFormatter Unit Tests

    @Test("StatusDashboardFormatter — plain 输出包含所有字段")
    func dashboardPlainContainsAllFields() {
        let stats = makeStats()
        let output = StatusDashboardFormatter.format(
            stats: stats,
            isTTY: false,  // Use plain mode for predictable assertions
            profile: .unknown
        )
        #expect(output.contains("claude-sonnet-4"))
        #expect(output.contains("default"))
        #expect(output.contains("test-ses"))  // first 8 chars
        #expect(output.contains("turns"))
        #expect(output.contains("5 tools"))
        #expect(output.contains("12K/200K"))
        #expect(output.contains("/tmp/project"))
    }

    @Test("StatusDashboardFormatter — 非 TTY 模式无 ANSI 转义")
    func dashboardPlainNoANSI() {
        let stats = makeStats()
        let output = StatusDashboardFormatter.format(
            stats: stats,
            isTTY: false,
            profile: .unknown
        )
        #expect(!output.contains("\u{1B}["))
        #expect(output.contains("Session Status"))
    }

    @Test("StatusDashboardFormatter — TTY 模式有 ANSI 转义和边框")
    func dashboardTTYHasBorder() {
        let stats = makeStats()
        let output = StatusDashboardFormatter.format(
            stats: stats,
            isTTY: true,
            profile: .trueColor
        )
        #expect(output.contains("\u{1B}["))
        #expect(output.contains("╭"))
        #expect(output.contains("╰"))
        #expect(output.contains("Model"))
        #expect(output.contains("Context"))
    }

    @Test("renderProgressBar — 不同百分比的颜色段")
    func progressBarColors() {
        // < 50%: green
        let green = StatusDashboardFormatter.renderProgressBar(pct: 0.3, profile: .trueColor)
        #expect(green.contains("█"))
        #expect(green.contains("░"))
        #expect(green.contains("\u{1B}[38;2;76;175;80m"))  // green

        // 50-80%: yellow
        let yellow = StatusDashboardFormatter.renderProgressBar(pct: 0.65, profile: .trueColor)
        #expect(yellow.contains("\u{1B}[38;2;234;179;8m"))  // yellow

        // > 80%: red
        let red = StatusDashboardFormatter.renderProgressBar(pct: 0.9, profile: .trueColor)
        #expect(red.contains("\u{1B}[38;2;244;67;54m"))  // red
    }

    @Test("renderProgressBar — 0% 和 100% 边界")
    func progressBarBoundaries() {
        let empty = StatusDashboardFormatter.renderProgressBar(pct: 0.0, profile: .ansi256)
        #expect(!empty.contains("█"))
        #expect(empty.contains("░"))

        let full = StatusDashboardFormatter.renderProgressBar(pct: 1.0, profile: .ansi256)
        #expect(full.contains("█"))
        #expect(!full.contains("░"))
    }

    @Test("renderProgressBar — unknown profile 仍输出进度条字符")
    func progressBarUnknownProfile() {
        let bar = StatusDashboardFormatter.renderProgressBar(pct: 0.5, profile: .unknown)
        // unknown profile may still emit reset codes from the filled portion
        #expect(bar.contains("█"))
        #expect(bar.contains("░"))
    }

    @Test("formatElapsedDuration — 各种时长格式")
    func elapsedDurationFormatting() {
        // Using manual Duration construction
        let d30s = ContinuousClock.Duration(secondsComponent: 30, attosecondsComponent: 0)
        #expect(StatusDashboardFormatter.formatElapsedDuration(d30s) == "30s")

        let d90s = ContinuousClock.Duration(secondsComponent: 90, attosecondsComponent: 0)
        #expect(StatusDashboardFormatter.formatElapsedDuration(d90s) == "1m 30s")

        let d1h = ContinuousClock.Duration(secondsComponent: 3600, attosecondsComponent: 0)
        #expect(StatusDashboardFormatter.formatElapsedDuration(d1h) == "1h")

        let d90m = ContinuousClock.Duration(secondsComponent: 5400, attosecondsComponent: 0)
        #expect(StatusDashboardFormatter.formatElapsedDuration(d90m) == "1h 30m")

        let d2d = ContinuousClock.Duration(secondsComponent: 172800, attosecondsComponent: 0)
        #expect(StatusDashboardFormatter.formatElapsedDuration(d2d) == "2d 0h")  // always shows hours for days

        let d25h = ContinuousClock.Duration(secondsComponent: 90000, attosecondsComponent: 0)
        #expect(StatusDashboardFormatter.formatElapsedDuration(d25h) == "1d 1h")
    }

    @Test("formatTokenCount — K/M 格式化")
    func tokenCountFormatting() {
        #expect(StatusDashboardFormatter.formatTokenCount(42) == "42")
        #expect(StatusDashboardFormatter.formatTokenCount(999) == "999")
        #expect(StatusDashboardFormatter.formatTokenCount(1000) == "1.0K")
        #expect(StatusDashboardFormatter.formatTokenCount(5500) == "5.5K")
        #expect(StatusDashboardFormatter.formatTokenCount(15000) == "15K")
        #expect(StatusDashboardFormatter.formatTokenCount(1_000_000) == "1.0M")
        #expect(StatusDashboardFormatter.formatTokenCount(2_500_000) == "2.5M")
    }

    @Test("SessionStats — session elapsed duration 显示在输出中")
    func dashboardShowsElapsedTime() {
        let stats = makeStats()
        let output = StatusDashboardFormatter.format(
            stats: stats,
            isTTY: false,
            profile: .unknown
        )
        // Plain mode shows "Duration: Xs, N turns, M tools"
        #expect(output.contains("Duration:"))
        #expect(output.contains("0s"))
        #expect(output.contains("3 turns"))
        #expect(output.contains("5 tools"))
    }

    @Test("SessionStats — context 进度条颜色随使用率变化")
    func dashboardContextColorChanges() {
        // Low usage
        let lowStats = StatusDashboardFormatter.SessionStats(
            model: "test",
            permissionMode: "default",
            sessionId: "session-1",
            sessionStartTime: .now,
            turnCount: 1,
            totalToolsUsed: 0,
            contextTokens: 10000,
            contextWindow: 200000,
            usage: StatusDashboardFormatter.TokenUsageEstimate(
                inputTokens: 1000, outputTokens: 500, cacheReadTokens: 0, totalTokens: 1500
            ),
            estimatedCost: nil,
            cwd: "/tmp",
            toolUsage: nil
        )
        let lowOutput = StatusDashboardFormatter.format(
            stats: lowStats, isTTY: true, profile: .trueColor
        )
        // 5% usage → green progress bar
        #expect(lowOutput.contains("\u{1B}[38;2;76;175;80m"))

        // High usage
        let highStats = StatusDashboardFormatter.SessionStats(
            model: "test",
            permissionMode: "default",
            sessionId: "session-1",
            sessionStartTime: .now,
            turnCount: 1,
            totalToolsUsed: 0,
            contextTokens: 180000,
            contextWindow: 200000,
            usage: StatusDashboardFormatter.TokenUsageEstimate(
                inputTokens: 1000, outputTokens: 500, cacheReadTokens: 0, totalTokens: 1500
            ),
            estimatedCost: nil,
            cwd: "/tmp",
            toolUsage: nil
        )
        let highOutput = StatusDashboardFormatter.format(
            stats: highStats, isTTY: true, profile: .trueColor
        )
        // 90% usage → red progress bar
        #expect(highOutput.contains("\u{1B}[38;2;244;67;54m"))
    }

    // MARK: - handleStatus Integration Tests

    @Test("handleStatus — 新仪表板格式包含会话统计")
    func handleStatusDashboardFormat() {
        let usage = TokenUsage(inputTokens: 45000, outputTokens: 12000)
        let startTime = ContinuousClock.now - ContinuousClock.Duration(secondsComponent: 120, attosecondsComponent: 0)
        let output = SlashCommandHandler.handleStatus(
            model: "claude-sonnet-4-20250514",
            permissionMode: "bypassPermissions",
            sessionId: "chat-20260607abcd",
            contextTokens: 12345,
            contextWindow: 200000,
            cwd: "/Users/nick/project",
            usage: usage,
            sessionStartTime: startTime,
            turnCount: 7,
            totalToolsUsed: 15,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(output.contains("claude-sonnet-4-20250514"))
        #expect(output.contains("bypassPermissions"))
        #expect(output.contains("chat-202"))  // first 8 chars of "chat-20260607abcd"
        #expect(output.contains("7 turns"))
        #expect(output.contains("15 tools"))
        #expect(output.contains("/Users/nick/project"))
    }

    @Test("handleStatus — 零 token 用量")
    func handleStatusZeroTokens() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        let output = SlashCommandHandler.handleStatus(
            model: "test",
            permissionMode: "default",
            sessionId: "session-1234",
            contextTokens: 0,
            contextWindow: 200000,
            cwd: "/tmp",
            usage: usage,
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(output.contains("test"))
        #expect(output.contains("0 turns"))
        #expect(output.contains("0 tools"))
    }

    // MARK: - Test Helpers

    private func makeStats() -> StatusDashboardFormatter.SessionStats {
        StatusDashboardFormatter.SessionStats(
            model: "claude-sonnet-4",
            permissionMode: "default",
            sessionId: "test-session-id",
            sessionStartTime: ContinuousClock.now,
            turnCount: 3,
            totalToolsUsed: 5,
            contextTokens: 12345,
            contextWindow: 200000,
            usage: StatusDashboardFormatter.TokenUsageEstimate(
                inputTokens: 45000, outputTokens: 12000, cacheReadTokens: 5000, totalTokens: 62000
            ),
            estimatedCost: "$0.05",
            cwd: "/tmp/project",
            toolUsage: nil
        )
    }
}
