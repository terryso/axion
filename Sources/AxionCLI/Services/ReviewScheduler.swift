import Foundation
import os
import OpenAgentSDK

import AxionCore

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
        onReviewResult: (@Sendable (ReviewResultEvent) async -> Void)? = nil
    ) {
        self.noReview = noReview
        self.noMemory = noMemory
        self.reviewDataContext = reviewDataContext
        self.traceDir = traceDir
        self._onReviewResult = onReviewResult
    }

    func setOnReviewResult(_ handler: (@Sendable (ReviewResultEvent) async -> Void)?) {
        _onReviewResult = handler
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard !noReview else { return }
        guard !noMemory else { return }
        guard event is AgentCompletedEvent else { return }
        guard let orchestrator = reviewDataContext.reviewOrchestrator else { return }

        let messageCount = context.runCompleteContext?.numTurns ?? 0
        let reviewConfig = ReviewAgentConfig()
        let (doMemory, doSkill) = orchestrator.shouldReview(
            sessionId: context.sessionId ?? "",
            messageCount: messageCount,
            config: reviewConfig
        )

        guard doMemory || doSkill else { return }

        guard let agent = reviewDataContext.agent else {
            let logger = Logger(subsystem: "com.axion.cli", category: "ReviewScheduler")
            logger.warning("Review scheduled but agent not available — skipping")
            return
        }
        let messages = reviewDataContext.messages
        let tunedConfig = ReviewAgentConfig(reviewMemory: doMemory, reviewSkills: doSkill)
        let sessionId = context.sessionId ?? "unknown"
        let traceDir = self.traceDir

        let lastReviewAtBox = self._lastReviewAtBox
        let lastReviewSummaryBox = self._lastReviewSummaryBox
        let eventBus = context.eventBus
        let onReviewResult = self._onReviewResult
        let reviewStartTime = ContinuousClock.now

        _Concurrency.Task.detached { [orchestrator, agent, messages, tunedConfig, sessionId, traceDir, lastReviewAtBox, lastReviewSummaryBox, eventBus, onReviewResult, reviewStartTime] in
            let result = await orchestrator.executeReview(
                parentAgent: agent,
                messages: messages,
                config: tunedConfig
            )

            let elapsed = ContinuousClock.now - reviewStartTime
            let durationMs = Int(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)

            if let result {
                TraceRecorder.recordReviewCompleted(
                    runId: sessionId,
                    reviewSummary: result.summary,
                    memoryChanges: result.memoryChanges,
                    skillChanges: result.skillChanges,
                    traceDir: traceDir
                )

                if !result.memoryChanges.isEmpty || !result.skillChanges.isEmpty {
                    var parts: [String] = []
                    if !result.memoryChanges.isEmpty {
                        parts.append("新增 \(result.memoryChanges.count) 条记忆")
                    }
                    if !result.skillChanges.isEmpty {
                        parts.append("更新 \(result.skillChanges.count) 个技能")
                    }
                    fputs("[axion] Review: \(parts.joined(separator: ", "))\n", stderr)
                }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                lastReviewAtBox.set(formatter.string(from: Date()))

                let summaryText: String
                if !result.memoryChanges.isEmpty || !result.skillChanges.isEmpty {
                    var parts: [String] = []
                    if !result.memoryChanges.isEmpty {
                        parts.append("新增 \(result.memoryChanges.count) 条记忆")
                    }
                    if !result.skillChanges.isEmpty {
                        parts.append("更新 \(result.skillChanges.count) 个技能")
                    }
                    summaryText = parts.joined(separator: ", ")
                } else {
                    summaryText = result.summary
                }
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
                let logger = Logger(subsystem: "com.axion.cli", category: "ReviewScheduler")
                logger.warning("Review agent returned nil for session \(sessionId)")
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
}
