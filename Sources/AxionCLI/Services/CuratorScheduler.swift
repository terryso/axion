import Foundation
import os
import OpenAgentSDK

import AxionCore

/// Curator result info for optional TG push callback.
struct CuratorResultInfo: Sendable {
    let consolidations: Int
    let prunings: Int
    let autoTransitions: Int
    let success: Bool
    let durationMs: Int
    let error: String?
}

/// Protocol abstracting curator execution for testability.
protocol CuratorExecuting: Sendable {
    func execute(parentAgent: Agent, dryRun: Bool) async throws -> IntelligentCuratorResult
}

extension IntelligentCurator: CuratorExecuting {}

/// EventHandler that schedules background curator runs when the gateway is idle.
///
/// Subscribes to `AgentCompletedEvent` and `AgentFailedEvent` to track last task time.
/// When idle time exceeds `curatorIdleHours` AND interval since last curator exceeds
/// `curatorIntervalHours`, launches a detached curator task.
actor CuratorScheduler: EventHandler {
    let identifier = "curator-scheduler"
    let subscribedEventTypes: [any AgentEvent.Type] = [AgentCompletedEvent.self, AgentFailedEvent.self]

    private let curatorIdleHours: Double
    private let curatorIntervalHours: Double
    private let curator: any CuratorExecuting
    private let agentProvider: @Sendable () -> Agent?
    private let traceDir: String

    private var _lastTaskAt: Date?
    private var _lastCuratorAt: Date?

    private let _lastCuratorAtBox: LockedStringBox = LockedStringBox()

    private var _onCuratorResult: (@Sendable (CuratorResultInfo) async -> Void)?

    /// ISO8601-formatted timestamp of the last successful curator, or nil.
    nonisolated var lastCuratorAtValue: String? { _lastCuratorAtBox.value }

    init(
        curatorIdleHours: Double,
        curatorIntervalHours: Double,
        curator: any CuratorExecuting,
        agentProvider: @Sendable @escaping () -> Agent?,
        traceDir: String,
        onCuratorResult: (@Sendable (CuratorResultInfo) async -> Void)? = nil
    ) {
        self.curatorIdleHours = curatorIdleHours
        self.curatorIntervalHours = curatorIntervalHours
        self.curator = curator
        self.agentProvider = agentProvider
        self.traceDir = traceDir
        self._onCuratorResult = onCuratorResult
    }

    func setOnCuratorResult(_ handler: (@Sendable (CuratorResultInfo) async -> Void)?) {
        _onCuratorResult = handler
    }

    /// Check if idle and interval conditions are met for a curator run.
    /// - Parameters:
    ///   - now: Current time to evaluate against.
    ///   - referenceLastTaskAt: Override for _lastTaskAt (used by handle() to pass the pre-update value).
    func shouldCurate(now: Date, referenceLastTaskAt: Date? = nil) -> Bool {
        let lastTask = referenceLastTaskAt ?? _lastTaskAt
        guard let lastTask else { return false }
        let idleSeconds = now.timeIntervalSince(lastTask)
        let idleHours = idleSeconds / 3600.0
        guard idleHours >= curatorIdleHours else { return false }

        if let lastCurator = _lastCuratorAt {
            let intervalSeconds = now.timeIntervalSince(lastCurator)
            let intervalHours = intervalSeconds / 3600.0
            guard intervalHours >= curatorIntervalHours else { return false }
        }

        return true
    }

    /// Entry point for periodic idle checks (external timer).
    func checkIdle() async {
        let now = Date()
        guard shouldCurate(now: now) else { return }
        guard let agent = agentProvider() else { return }

        _lastCuratorAt = now
        let curator = self.curator
        let traceDir = self.traceDir
        let lastCuratorAtBox = self._lastCuratorAtBox
        let onCuratorResult = self._onCuratorResult

        _Concurrency.Task.detached { [curator, agent, traceDir, lastCuratorAtBox, onCuratorResult] in
            await Self.executeCurator(
                curator: curator,
                agent: agent,
                traceDir: traceDir,
                lastCuratorAtBox: lastCuratorAtBox,
                onCuratorResult: onCuratorResult
            )
        }
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        let now = Date()
        // Check idle condition with the OLD _lastTaskAt BEFORE updating it.
        // If we update first, now - _lastTaskAt = 0 and idleHours is always 0.
        let previousLastTaskAt = _lastTaskAt
        _lastTaskAt = now

        guard shouldCurate(now: now, referenceLastTaskAt: previousLastTaskAt) else { return }
        guard let agent = agentProvider() else {
            let logger = Logger(subsystem: "com.axion.cli", category: "CuratorScheduler")
            logger.warning("Curator scheduled but agent not available — skipping")
            return
        }

        _lastCuratorAt = now

        let curator = self.curator
        let traceDir = self.traceDir
        let lastCuratorAtBox = self._lastCuratorAtBox
        let onCuratorResult = self._onCuratorResult
        let sessionId = context.sessionId ?? "unknown"

        _Concurrency.Task.detached { [curator, agent, traceDir, lastCuratorAtBox, onCuratorResult, sessionId] in
            await Self.executeCurator(
                curator: curator,
                agent: agent,
                traceDir: traceDir,
                lastCuratorAtBox: lastCuratorAtBox,
                onCuratorResult: onCuratorResult,
                sessionId: sessionId
            )
        }
    }

    private static func executeCurator(
        curator: any CuratorExecuting,
        agent: Agent,
        traceDir: String,
        lastCuratorAtBox: LockedStringBox,
        onCuratorResult: (@Sendable (CuratorResultInfo) async -> Void)?,
        sessionId: String = "curator-bg"
    ) async {
        let logger = Logger(subsystem: "com.axion.cli", category: "CuratorScheduler")
        do {
            let result = try await curator.execute(parentAgent: agent, dryRun: false)

            let report = CuratorRunReport(from: result)
            logger.debug("Curator report:\n\(report.renderMarkdown())")

            TraceRecorder.recordCuratorCompleted(
                runId: sessionId,
                consolidations: result.consolidations.count,
                prunings: result.prunings.count,
                transitionsApplied: result.mechanicalResult.transitionsApplied.count,
                traceDir: traceDir
            )

            if !result.consolidations.isEmpty || !result.prunings.isEmpty {
                var parts: [String] = []
                if !result.consolidations.isEmpty {
                    parts.append("合并 \(result.consolidations.count) 个技能")
                }
                if !result.prunings.isEmpty {
                    parts.append("归档 \(result.prunings.count) 个技能")
                }
                fputs("[axion] Curator: \(parts.joined(separator: ", "))\n", stderr)
            } else {
                fputs("[axion] Curator: 无变更，技能库已整洁\n", stderr)
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastCuratorAtBox.set(formatter.string(from: Date()))

            let info = CuratorResultInfo(
                consolidations: result.consolidations.count,
                prunings: result.prunings.count,
                autoTransitions: result.mechanicalResult.transitionsApplied.count,
                success: true,
                durationMs: result.durationMs,
                error: nil
            )
            await onCuratorResult?(info)
        } catch {
            logger.warning("Curator execution failed: \(error.localizedDescription)")
            TraceRecorder.recordCuratorFailed(
                runId: sessionId,
                error: error.localizedDescription,
                traceDir: traceDir
            )
            let info = CuratorResultInfo(
                consolidations: 0,
                prunings: 0,
                autoTransitions: 0,
                success: false,
                durationMs: 0,
                error: error.localizedDescription
            )
            await onCuratorResult?(info)
        }
    }
}
