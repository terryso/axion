import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - Pause Handling

extension RunOrchestrator {

    /// Result of handling a paused agent event.
    struct PauseEventResult: Sendable {
        let takeoverEvent: (issue: String, summary: String, feedback: String?, reason: String, duration: TimeInterval?)?
    }

    /// Handles a paused agent event — either interactively (CLI mode) or
    /// by publishing an event for external resume (gateway mode).
    ///
    /// - Parameters:
    ///   - pausedData: The paused event payload from the SDK.
    ///   - agent: The paused agent (for resume/interrupt calls).
    ///   - runConfig: The current run configuration.
    ///   - takeoverIO: I/O handler for the interactive takeover prompt.
    ///   - totalSteps: Completed steps count (shown in the takeover prompt).
    /// - Returns: A `PauseEventResult` with an optional takeover event context.
    static func handlePausedEvent(
        pausedData: SDKMessage.PausedData,
        agent: Agent,
        runConfig: RunConfig,
        takeoverIO: TakeoverIO,
        totalSteps: Int
    ) async -> PauseEventResult {
        if runConfig.nonInteractivePause {
            // Gateway mode: register resume handle, publish event, await external resume
            guard let registerHandle = runConfig.registerResumeHandle else {
                takeoverIO.write("[axion] warning: nonInteractivePause enabled but no registerResumeHandle — interrupting agent")
                agent.interrupt()
                return PauseEventResult(takeoverEvent: nil)
            }
            let pendingId = UUID().uuidString.prefix(8).lowercased()
            let resumeHandle: @Sendable (String) async -> Void = { context in
                agent.resume(context: context)
            }
            await registerHandle(String(pendingId), resumeHandle)
            await runConfig.eventBus?.publish(AgentPausedEvent(
                reason: pausedData.reason,
                sessionId: runConfig.task,
                canResume: true,
                pendingId: String(pendingId)
            ))
            return PauseEventResult(takeoverEvent: nil)
        }

        // CLI mode: interactive takeover prompt
        let takeoverStartTime = ContinuousClock.now
        let result = takeoverIO.displayTakeoverPrompt(
            reason: pausedData.reason,
            allowForeground: runConfig.allowForeground,
            completedSteps: totalSteps
        )
        switch result.action {
        case .resume:
            let userAction = result.userInput?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty == false
                ? result.userInput! : "用户已完成手动操作"
            takeoverIO.write("[axion] 正在恢复执行...")
            let elapsed = ContinuousClock.now - takeoverStartTime
            let durationSeconds = TakeoverMarker.durationToSeconds(elapsed)
            let takeoverEvent = (issue: pausedData.reason, summary: userAction, feedback: result.feedback, reason: pausedData.reason, duration: durationSeconds)
            agent.resume(context: userAction)
            return PauseEventResult(takeoverEvent: takeoverEvent)
        case .skip:
            agent.resume(context: "skip")
            return PauseEventResult(takeoverEvent: nil)
        case .abort:
            agent.interrupt()
            return PauseEventResult(takeoverEvent: nil)
        }
    }
}
