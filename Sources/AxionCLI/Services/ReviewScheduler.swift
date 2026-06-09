import Foundation
import os
import OpenAgentSDK


/// Thread-safe box for a single optional String value, readable without actor isolation.
final class LockedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: String?) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}

/// EventHandler that schedules background review agents after each run completes.
///
/// Subscribes to `AgentCompletedEvent`. When a run finishes, checks review intervals
/// via the injected orchestrator and launches a detached review task if conditions are met.
/// The review runs in isolation — tool whitelist is review-only (memory + skill), no MCP/Helper.
actor ReviewScheduler: EventHandler {
    let identifier = "review-scheduler"
    let subscribedEventTypes: [any AgentEvent.Type] = [AgentCompletedEvent.self]

    private let noReview: Bool
    private let noMemory: Bool
    private let reviewDataContext: ReviewDataContext
    private let traceDir: String
    private let memoryDir: String
    private let gatewaySessionStore: GatewaySessionStore?

    /// Thread-safe box for lastReviewAt, readable without actor isolation.
    private let _lastReviewAtBox: LockedStringBox = LockedStringBox()

    /// Thread-safe box for lastReviewSummary, readable without actor isolation.
    private let _lastReviewSummaryBox: LockedStringBox = LockedStringBox()

    /// Direct callback invoked when a review completes, bypassing the per-request EventBus.
    /// Used because the per-request event loop stops before the detached review task finishes.
    private var _onReviewResult: (@Sendable (ReviewResultEvent) async -> Void)?

    /// ISO8601-formatted timestamp of the last successful review, or nil.
    /// Safe to read from any isolation domain (nonisolated).
    nonisolated var lastReviewAtValue: String? { _lastReviewAtBox.value }

    /// Human-readable summary of the last successful review, or nil.
    /// Safe to read from any isolation domain (nonisolated).
    nonisolated var lastReviewSummaryValue: String? { _lastReviewSummaryBox.value }

    init(
        noReview: Bool,
        noMemory: Bool,
        reviewDataContext: ReviewDataContext,
        traceDir: String,
        memoryDir: String = ConfigManager.memoryDirectory,
        gatewaySessionStore: GatewaySessionStore? = nil,
        onReviewResult: (@Sendable (ReviewResultEvent) async -> Void)? = nil
    ) {
        self.noReview = noReview
        self.noMemory = noMemory
        self.reviewDataContext = reviewDataContext
        self.traceDir = traceDir
        self.memoryDir = memoryDir
        self.gatewaySessionStore = gatewaySessionStore
        self._onReviewResult = onReviewResult
    }

    func setOnReviewResult(_ handler: (@Sendable (ReviewResultEvent) async -> Void)?) {
        _onReviewResult = handler
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard !noReview else { return }
        guard !noMemory else { return }
        guard event is AgentCompletedEvent else { return }

        guard context.shouldReviewMemory else { return }

        guard let agent = reviewDataContext.agent else {
            axionReviewSchedulerLogger.warning("Review scheduled but agent not available — skipping")
            return
        }
        guard let orchestrator = reviewDataContext.reviewOrchestrator else { return }
        guard let chatId = context.chatId else { return }

        let sessionStore = context.sessionStore

        var tunedConfig = ReviewAgentConfig(reviewMemory: true, reviewSkills: false)
        tunedConfig.allowedTools.append("review_save_universal_memory")
        tunedConfig.promptSuffix = """
            **Universal Memory**: In addition to `review_save_memory`, you also have access \
            to `review_save_universal_memory`. Use it to persist durable user preferences, \
            persona facts, and behavioral expectations that should survive across sessions. \
            Actions: `add` (append an entry), `replace` (replace all content). \
            Targets: `user` (personal preferences, style), `memory` (project/environment facts). \
            Prefer `review_save_universal_memory` over `review_save_memory` for style, language, \
            and interaction preferences that the user wants applied every time.
            """
        let sessionId = context.sessionId ?? "unknown"
        let traceDir = self.traceDir
        let memoryDir = self.memoryDir
        let gatewayStore = self.gatewaySessionStore

        let lastReviewAtBox = self._lastReviewAtBox
        let lastReviewSummaryBox = self._lastReviewSummaryBox
        let eventBus = context.eventBus
        let onReviewResult = self._onReviewResult
        let reviewStartTime = ContinuousClock.now

        _Concurrency.Task.detached { [orchestrator, agent, tunedConfig, sessionId, chatId, sessionStore, traceDir, memoryDir, gatewayStore, lastReviewAtBox, lastReviewSummaryBox, eventBus, onReviewResult, reviewStartTime] in
            // Load current run's messages (wait for post-stream write)
            let dataContext = self.reviewDataContext
            let currentMessages = await dataContext.waitForMessages()

            // Load full conversation history from all sessions for this chatId
            var allMessages: [SDKMessage] = []

            // Collect all sessionIds for this chatId from GatewaySessionStore
            let state = await gatewayStore?.state(for: chatId)
            let olderSessionIds = state?.sessionIds.filter { $0 != sessionId } ?? []

            // Load older session transcripts and convert to SDKMessage
            for olderSid in olderSessionIds {
                if let sessionData = try? await sessionStore.load(sessionId: olderSid) {
                    allMessages.append(contentsOf: Self.convertTranscriptMessages(sessionData.messages))
                }
            }

            // Append current run's messages (most reliable — already as SDKMessage)
            allMessages.append(contentsOf: currentMessages)

            // Fallback: if no history loaded, use current messages alone
            let messages = allMessages.isEmpty ? currentMessages : allMessages

            let reviewResult = await orchestrator.executeReview(
                parentAgent: agent,
                messages: messages,
                config: tunedConfig
            )
            let result = await Self.applyUniversalMemoryFallbackIfNeeded(
                reviewResult: reviewResult,
                messages: messages,
                config: tunedConfig,
                memoryDir: memoryDir
            )

            let durationMs = durationToMs(ContinuousClock.now - reviewStartTime)

            if let result {
                TraceRecorder.recordReviewCompleted(
                    runId: sessionId,
                    reviewSummary: result.summary,
                    memoryChanges: result.memoryChanges,
                    skillChanges: result.skillChanges,
                    traceDir: traceDir
                )

                if let changeSummary = Self.formatChangeSummary(memoryChanges: result.memoryChanges, skillChanges: result.skillChanges) {
                    fputs("[axion] Review: \(changeSummary)\n", stderr)
                }

                lastReviewAtBox.set(axionISO8601Formatter.string(from: Date()))

                let summaryText = Self.formatChangeSummary(memoryChanges: result.memoryChanges, skillChanges: result.skillChanges) ?? result.summary
                lastReviewSummaryBox.set(summaryText)

                let event = ReviewResultEvent(
                    summary: result.summary,
                    memoryChanges: result.memoryChanges,
                    skillChanges: result.skillChanges,
                    success: true,
                    durationMs: durationMs,
                    sessionId: sessionId
                )
                if let eventBus {
                    await eventBus.publish(event)
                }
                await onReviewResult?(event)
            } else {
                axionReviewSchedulerLogger.warning("Review agent returned nil for session \(sessionId)")
                TraceRecorder.recordReviewFailed(
                    runId: sessionId,
                    error: "review agent returned nil",
                    traceDir: traceDir
                )

                let event = ReviewResultEvent(
                    summary: "review agent returned nil",
                    memoryChanges: [],
                    skillChanges: [],
                    success: false,
                    durationMs: durationMs,
                    sessionId: sessionId
                )
                if let eventBus {
                    await eventBus.publish(event)
                }
                await onReviewResult?(event)
            }
        }
    }

    // MARK: - Shared Helpers

    /// Format a human-readable summary of memory and skill changes.
    /// Returns nil if there are no changes.
    static func formatChangeSummary(memoryChanges: [String], skillChanges: [String]) -> String? {
        guard !memoryChanges.isEmpty || !skillChanges.isEmpty else { return nil }
        var parts: [String] = []
        if !memoryChanges.isEmpty {
            parts.append("新增 \(memoryChanges.count) 条记忆")
        }
        if !skillChanges.isEmpty {
            parts.append("更新 \(skillChanges.count) 个技能")
        }
        return parts.joined(separator: ", ")
    }

}
