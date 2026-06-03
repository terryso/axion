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
    private let memoryDir: String

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
        memoryDir: String = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory"),
        onReviewResult: (@Sendable (ReviewResultEvent) async -> Void)? = nil
    ) {
        self.noReview = noReview
        self.noMemory = noMemory
        self.reviewDataContext = reviewDataContext
        self.traceDir = traceDir
        self.memoryDir = memoryDir
        self._onReviewResult = onReviewResult
    }

    func setOnReviewResult(_ handler: (@Sendable (ReviewResultEvent) async -> Void)?) {
        _onReviewResult = handler
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard !noReview else { return }
        guard !noMemory else { return }
        guard let completedEvent = event as? AgentCompletedEvent else { return }
        guard let orchestrator = reviewDataContext.reviewOrchestrator else { return }

        // Use totalSteps from the event itself — context.runCompleteContext is nil
        // during event dispatch because the run hasn't returned yet.
        let messageCount = completedEvent.totalSteps
        var reviewConfig = ReviewAgentConfig()
        reviewConfig.allowedTools.append("review_save_universal_memory")
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
        // Capture reviewDataContext reference so detached Task reads messages lazily
        // (messages may not be populated until post-stream update completes)
        let dataContext = self.reviewDataContext
        var tunedConfig = ReviewAgentConfig(reviewMemory: doMemory, reviewSkills: doSkill)
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

        let lastReviewAtBox = self._lastReviewAtBox
        let lastReviewSummaryBox = self._lastReviewSummaryBox
        let eventBus = context.eventBus
        let onReviewResult = self._onReviewResult
        let reviewStartTime = ContinuousClock.now

        _Concurrency.Task.detached { [orchestrator, agent, dataContext, tunedConfig, sessionId, traceDir, memoryDir, lastReviewAtBox, lastReviewSummaryBox, eventBus, onReviewResult, reviewStartTime] in
            // Wait for post-stream messages — RunOrchestrator writes them after the
            // stream ends, which may race with this detached Task.
            let messages = await dataContext.waitForMessages()
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

    private static func applyUniversalMemoryFallbackIfNeeded(
        reviewResult: ReviewAgentResult?,
        messages: [SDKMessage],
        config: ReviewAgentConfig,
        memoryDir: String
    ) async -> ReviewAgentResult? {
        guard config.reviewMemory else { return reviewResult }
        if let reviewResult, !reviewResult.memoryChanges.isEmpty { return reviewResult }

        var fallbackMemoryChanges: [String] = []

        if let preference = extractExplicitUserPreference(from: messages) {
            let store = UniversalMemoryStore(memoryDir: memoryDir)
            let existing = await store.read(target: .user)
            if !existing.contains(preference) {
                let scanner = MemorySecurityScanner()
                if case .safe = scanner.scan(content: preference) {
                    let saved = await store.add(target: .user, content: preference)
                    if saved {
                        fallbackMemoryChanges.append("Saved entry to USER.md")
                    }
                }
            }
        }

        guard !fallbackMemoryChanges.isEmpty else { return reviewResult }

        let skillChanges = reviewResult?.skillChanges ?? []
        let reviewMessages = reviewResult?.reviewMessages ?? []
        return ReviewAgentResult(
            memoryChanges: fallbackMemoryChanges,
            skillChanges: skillChanges,
            summary: "Review completed: " + fallbackMemoryChanges.joined(separator: "; "),
            reviewMessages: reviewMessages
        )
    }

    // Fallback: catches explicit Chinese-language preference patterns that the review agent
    // may miss. The primary path is now the review agent using review_save_universal_memory
    // (guided by promptSuffix in ReviewAgentConfig).
    private static func extractExplicitUserPreference(from messages: [SDKMessage]) -> String? {
        let styleKeywords = ["回答", "回复", "emoji", "表情", "简洁", "详细", "中文", "英文", "格式", "语气", "解释", "markdown"]
        let futureMarkers = ["以后", "今后", "之后", "后续", "下次"]
        let directPrefixes = ["别", "不要", "请", "用中文", "用英文", "回答", "回复"]

        for message in messages.reversed() {
            guard case .userMessage(let data) = message else { continue }
            let trimmed = data.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let clause = splitPreferenceClause(from: trimmed)
            let hasStyleKeyword = styleKeywords.contains(where: { clause.localizedCaseInsensitiveContains($0) })
            let hasFutureMarker = futureMarkers.contains(where: { clause.contains($0) })
            let hasDirectPrefix = directPrefixes.contains(where: { clause.hasPrefix($0) })

            if hasStyleKeyword && (hasFutureMarker || hasDirectPrefix) {
                return clause
            }
        }

        return nil
    }

    private static func splitPreferenceClause(from message: String) -> String {
        let separators = ["，并", "，然后", "，再", ", and", " and then ", " then "]
        for separator in separators {
            if let range = message.range(of: separator, options: [.caseInsensitive]) {
                return String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let range = message.range(of: "，") {
            return String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
