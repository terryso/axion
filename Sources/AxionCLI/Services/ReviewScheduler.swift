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

    /// ISO8601-formatted timestamp of the last successful review, or nil.
    /// Safe to read from any isolation domain (nonisolated).
    nonisolated var lastReviewAtValue: String? { _lastReviewAtBox.value }

    init(
        noReview: Bool,
        noMemory: Bool,
        reviewDataContext: ReviewDataContext,
        traceDir: String
    ) {
        self.noReview = noReview
        self.noMemory = noMemory
        self.reviewDataContext = reviewDataContext
        self.traceDir = traceDir
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

        _Concurrency.Task.detached { [orchestrator, agent, messages, tunedConfig, sessionId, traceDir, lastReviewAtBox] in
            let result = await orchestrator.executeReview(
                parentAgent: agent,
                messages: messages,
                config: tunedConfig
            )

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
                        parts.append("更新了 \(result.skillChanges.count) 个技能")
                    }
                    fputs("[axion] Review: \(parts.joined(separator: ", "))\n", stderr)
                }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                lastReviewAtBox.set(formatter.string(from: Date()))
            } else {
                let logger = Logger(subsystem: "com.axion.cli", category: "ReviewScheduler")
                logger.warning("Review agent returned nil for session \(sessionId)")
                TraceRecorder.recordReviewFailed(
                    runId: sessionId,
                    error: "review agent returned nil",
                    traceDir: traceDir
                )
            }
        }
    }
}
