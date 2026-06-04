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
        memoryDir: String = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory"),
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
            let logger = Logger(subsystem: "com.axion.cli", category: "ReviewScheduler")
            logger.warning("Review scheduled but agent not available — skipping")
            return
        }
        guard let orchestrator = reviewDataContext.reviewOrchestrator else { return }
        guard let chatId = context.chatId else { return }

        let sessionStore = context.sessionStore
        let currentSessionId = context.sessionId

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

    /// Convert transcript `[[String: Any]]` dicts (from SessionStore) to `[SDKMessage]`.
    private static func convertTranscriptMessages(_ rawMessages: [[String: Any]]) -> [SDKMessage] {
        rawMessages.compactMap { dict -> SDKMessage? in
            let role = dict["type"] as? String ?? dict["role"] as? String ?? ""
            switch role {
            case "user":
                let content = dict["message"] as? String ?? dict["content"] as? String ?? ""
                guard !content.isEmpty else { return nil }
                return .userMessage(SDKMessage.UserMessageData(
                    uuid: dict["uuid"] as? String,
                    sessionId: dict["session_id"] as? String ?? dict["sessionId"] as? String,
                    message: content,
                    parentToolUseId: dict["parent_tool_use_id"] as? String ?? dict["parentToolUseId"] as? String
                ))
            case "assistant":
                let text = dict["message"] as? String ?? dict["content"] as? String ?? ""
                guard !text.isEmpty else { return nil }
                return .assistant(SDKMessage.AssistantData(
                    text: text,
                    model: dict["model"] as? String ?? "unknown",
                    stopReason: dict["stop_reason"] as? String ?? "end_turn",
                    uuid: dict["uuid"] as? String,
                    sessionId: dict["session_id"] as? String ?? dict["sessionId"] as? String
                ))
            default:
                return nil
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
