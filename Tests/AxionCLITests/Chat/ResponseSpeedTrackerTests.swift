import Testing
import Foundation

@testable import AxionCLI
import OpenAgentSDK

@Suite("ResponseSpeedTracker Tests")
struct ResponseSpeedTrackerTests {

    // MARK: - Tracker Initialization

    @Test("Initial state has no first token")
    func initialState() {
        let tracker = ResponseSpeedTracker()
        #expect(tracker.firstTokenTime == nil)
        #expect(!tracker.hasFirstToken)
    }

    @Test("markFirstToken sets first token time")
    func markFirstToken() {
        var tracker = ResponseSpeedTracker()
        let now: ContinuousClock.Instant = .now
        tracker.markFirstToken(now: now)
        #expect(tracker.hasFirstToken)
        #expect(tracker.firstTokenTime == now)
    }

    @Test("markFirstToken is idempotent — only records first call")
    func markFirstTokenIdempotent() {
        var tracker = ResponseSpeedTracker()
        let time1: ContinuousClock.Instant = .now
        tracker.markFirstToken(now: time1)

        // Second call should be ignored
        let time2 = time1 + .milliseconds(500)
        tracker.markFirstToken(now: time2)
        #expect(tracker.firstTokenTime == time1)
    }

    // MARK: - Speed Computation

    @Test("computeSpeed returns nil without first token")
    func computeSpeedWithoutFirstToken() {
        let tracker = ResponseSpeedTracker()
        #expect(tracker.computeSpeed(outputTokens: 100) == nil)
    }

    @Test("computeSpeed calculates correct thinking and streaming duration")
    func computeSpeedBasic() {
        let start: ContinuousClock.Instant = .now
        var tracker = ResponseSpeedTracker(turnStartTime: start)

        let firstToken = start + .milliseconds(800)
        tracker.markFirstToken(now: firstToken)

        let endTime = start + .milliseconds(3000)
        let speed = tracker.computeSpeed(outputTokens: 300, endTime: endTime)

        #expect(speed != nil)
        let s = speed!
        // Thinking: 800ms
        #expect(durationToMs(s.thinkingDuration) == 800)
        // Streaming: 2200ms
        #expect(durationToMs(s.streamingDuration) == 2200)
        // tok/s: 300 / 2.2 ≈ 136
        #expect(s.tokensPerSecond != nil)
        #expect(s.tokensPerSecond! > 130 && s.tokensPerSecond! < 140)
    }

    @Test("computeSpeed returns nil tok/s for zero output tokens")
    func computeSpeedZeroTokens() {
        let start: ContinuousClock.Instant = .now
        var tracker = ResponseSpeedTracker(turnStartTime: start)
        tracker.markFirstToken(now: start + .milliseconds(500))

        let speed = tracker.computeSpeed(outputTokens: 0, endTime: start + .milliseconds(2000))
        #expect(speed != nil)
        #expect(speed!.tokensPerSecond == nil)
    }

    @Test("computeSpeed handles very fast response")
    func computeSpeedFastResponse() {
        let start: ContinuousClock.Instant = .now
        var tracker = ResponseSpeedTracker(turnStartTime: start)

        // Very fast: think 50ms, stream 100ms, 50 tokens
        tracker.markFirstToken(now: start + .milliseconds(50))
        let speed = tracker.computeSpeed(outputTokens: 50, endTime: start + .milliseconds(150))

        #expect(speed != nil)
        #expect(durationToMs(speed!.thinkingDuration) == 50)
        #expect(durationToMs(speed!.streamingDuration) == 100)
        // 50 tokens / 0.1s = 500 tok/s
        #expect(speed!.tokensPerSecond == 500.0)
    }

    @Test("computeSpeed handles slow response")
    func computeSpeedSlowResponse() {
        let start: ContinuousClock.Instant = .now
        var tracker = ResponseSpeedTracker(turnStartTime: start)

        // Slow: think 3000ms, stream 5000ms, 500 tokens
        tracker.markFirstToken(now: start + .milliseconds(3000))
        let speed = tracker.computeSpeed(outputTokens: 500, endTime: start + .milliseconds(8000))

        #expect(speed != nil)
        #expect(durationToMs(speed!.thinkingDuration) == 3000)
        #expect(durationToMs(speed!.streamingDuration) == 5000)
        // 500 tokens / 5.0s = 100 tok/s
        #expect(speed!.tokensPerSecond == 100.0)
    }

    // MARK: - ResponseSpeed Formatting

    @Test("formatCompact with thinking and speed")
    func formatCompactWithBoth() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(800),
            streamingDuration: Duration.milliseconds(2200),
            tokensPerSecond: 136.4
        )
        let result = speed.formatCompact()
        #expect(result != nil)
        #expect(result!.contains("think"))
        #expect(result!.contains("136 tok/s"))
    }

    @Test("formatCompact rounds speed >= 100")
    func formatCompactRoundsHighSpeed() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(500),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 1234.56
        )
        let result = speed.formatCompact()
        #expect(result != nil)
        #expect(result!.contains("1235 tok/s"))
    }

    @Test("formatCompact with only thinking time")
    func formatCompactThinkingOnly() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(1500),
            streamingDuration: Duration.milliseconds(0),
            tokensPerSecond: nil
        )
        let result = speed.formatCompact()
        #expect(result == "think 1.5s")
    }

    @Test("formatCompact with only speed")
    func formatCompactSpeedOnly() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(0),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 50.0
        )
        let result = speed.formatCompact()
        #expect(result == "50 tok/s")
    }

    @Test("formatCompact returns nil with no data")
    func formatCompactNoData() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(0),
            streamingDuration: Duration.milliseconds(0),
            tokensPerSecond: nil
        )
        #expect(speed.formatCompact() == nil)
    }

    @Test("formatPlain uses comma separator")
    func formatPlainCommaSeparator() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(800),
            streamingDuration: Duration.milliseconds(2200),
            tokensPerSecond: 86.0
        )
        let result = speed.formatPlain()
        #expect(result != nil)
        #expect(result!.contains(","))
        #expect(result!.contains("think"))
        #expect(result!.contains("86 tok/s"))
    }

    @Test("formatPlain returns nil with no data")
    func formatPlainNoData() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(0),
            streamingDuration: Duration.milliseconds(0),
            tokensPerSecond: nil
        )
        #expect(speed.formatPlain() == nil)
    }

    // MARK: - ResponseSpeed Equality

    @Test("ResponseSpeed equality")
    func responseSpeedEquality() {
        let a = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(500),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 100.0
        )
        let b = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(500),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 100.0
        )
        #expect(a == b)
    }

    @Test("ResponseSpeed inequality")
    func responseSpeedInequality() {
        let a = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(500),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 100.0
        )
        let b = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(600),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 100.0
        )
        #expect(a != b)
    }

    // MARK: - Duration Formatting Edge Cases

    @Test("formatCompact with sub-second thinking")
    func formatCompactSubSecond() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(300),
            streamingDuration: Duration.milliseconds(200),
            tokensPerSecond: 250.0
        )
        let result = speed.formatCompact()
        #expect(result != nil)
        #expect(result!.contains("think 300ms"))
        #expect(result!.contains("250 tok/s"))
    }

    @Test("formatCompact with minute-level thinking")
    func formatCompactMinuteLevel() {
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(65_000),
            streamingDuration: Duration.milliseconds(120_000),
            tokensPerSecond: 8.0
        )
        let result = speed.formatCompact()
        #expect(result != nil)
        #expect(result!.contains("65.0s"))
        #expect(result!.contains("8 tok/s"))
    }

    // MARK: - Full Lifecycle

    @Test("Full lifecycle: start → first token → compute")
    func fullLifecycle() {
        let start: ContinuousClock.Instant = .now
        var tracker = ResponseSpeedTracker(turnStartTime: start)

        // No speed yet
        #expect(!tracker.hasFirstToken)
        #expect(tracker.computeSpeed(outputTokens: 100) == nil)

        // First token arrives after 1.2s
        let firstToken = start + .milliseconds(1200)
        tracker.markFirstToken(now: firstToken)
        #expect(tracker.hasFirstToken)

        // Turn ends at 6.2s total, 5.0s streaming, 500 output tokens
        let endTime = start + .milliseconds(6200)
        let speed = tracker.computeSpeed(outputTokens: 500, endTime: endTime)

        #expect(speed != nil)
        #expect(durationToMs(speed!.thinkingDuration) == 1200)
        #expect(durationToMs(speed!.streamingDuration) == 5000)
        #expect(speed!.tokensPerSecond == 100.0)

        // Format check
        let formatted = speed!.formatCompact()
        #expect(formatted != nil)
        #expect(formatted!.contains("think 1.2s"))
        #expect(formatted!.contains("100 tok/s"))
    }
}

@Suite("ResponseSpeed TranscriptRenderer Integration Tests")
struct ResponseSpeedRendererTests {

    /// Helper to create a TranscriptRenderer with TTY theme.
    private func makeTTYRenderer(profile: TerminalColorProfile = .ansi16) -> TranscriptRenderer {
        TranscriptRenderer(theme: ChatTheme(profile: profile, isTTY: true))
    }

    /// Helper to create a TranscriptRenderer with non-TTY theme.
    private func makePlainRenderer() -> TranscriptRenderer {
        TranscriptRenderer(theme: ChatTheme(profile: .unknown, isTTY: false))
    }

    // MARK: - Turn Summary with Response Speed

    @Test("Turn summary includes speed in TTY mode")
    func turnSummaryWithSpeedTTY() {
        let renderer = makeTTYRenderer()
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(800),
            streamingDuration: Duration.milliseconds(2200),
            tokensPerSecond: 136.0
        )
        let result = renderer.renderTurnSummary(
            duration: "3.0s",
            toolCount: 2,
            inputTokens: "1.2k",
            outputTokens: "856",
            contextPct: 45,
            estimatedCost: "$0.01",
            responseSpeed: speed
        )
        #expect(result.contains("(think 800ms"))
        #expect(result.contains("136 tok/s)"))
        #expect(result.contains("2 tools"))
        #expect(result.contains("↑1.2k ↓856"))
        #expect(result.contains("$0.01"))
        #expect(result.contains("──"))
    }

    @Test("Turn summary includes speed in plain mode")
    func turnSummaryWithSpeedPlain() {
        let renderer = makePlainRenderer()
        let speed = ResponseSpeed(
            thinkingDuration: Duration.milliseconds(500),
            streamingDuration: Duration.milliseconds(1000),
            tokensPerSecond: 86.0
        )
        let result = renderer.renderTurnSummary(
            duration: "1.5s",
            toolCount: 1,
            inputTokens: "500",
            outputTokens: "200",
            responseSpeed: speed
        )
        #expect(result.contains("[turn:"))
        #expect(result.contains("(think 500ms, 86 tok/s)"))
        #expect(result.contains("1 tool"))
        #expect(result.contains("↑500 ↓200"))
    }

    @Test("Turn summary without speed preserves original format")
    func turnSummaryWithoutSpeed() {
        let renderer = makeTTYRenderer()
        let result = renderer.renderTurnSummary(
            duration: "3.2s",
            toolCount: 2,
            inputTokens: "1.2k",
            outputTokens: "856",
            contextPct: 45,
            estimatedCost: "$0.01",
            responseSpeed: nil as ResponseSpeed?
        )
        #expect(!result.contains("think"))
        #expect(!result.contains("tok/s"))
        #expect(result.contains("── 3.2s · 2 tools · ↑1.2k ↓856"))
    }

    @Test("Turn summary backward compatible — existing callers work without speed param")
    func turnSummaryBackwardCompatible() {
        let renderer = makeTTYRenderer()
        let result = renderer.renderTurnSummary(
            duration: "2.1s",
            toolCount: 0,
            inputTokens: "300",
            outputTokens: "150"
        )
        #expect(result.contains("── 2.1s · 0 tools · ↑300 ↓150 ──"))
    }
}
