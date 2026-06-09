import Foundation
import os
import OpenAgentSDK

import AxionCore

/// Encapsulates the full agent execution pipeline: stream loop with output rendering,
/// takeover handling, and post-run processing (review + curator).
///
/// Visual delta, seat monitoring, cost tracking, and notification concerns are
/// handled by EventHandlers via EventBus.
///
/// Called by RunCommand (CLI) and could be reused by other execution contexts.
/// All configuration is passed via parameters — no mutable state.
///
/// Post-run processing and utility helpers are in companion extension files:
/// - `RunOrchestrator+PostRun.swift` — review, curator, and formatting
/// - `RunOrchestrator+Utilities.swift` — extraction, activation, notification helpers
enum RunOrchestrator {

    struct RunConfig: Sendable {
        let task: String
        let fast: Bool
        let dryrun: Bool
        let json: Bool
        let noMemory: Bool
        let noVisualDelta: Bool
        let allowForeground: Bool
        let maxSteps: Int?
        let config: AxionConfig
        let noReview: Bool
        let onReviewCompleted: (@Sendable (String) -> Void)?
        let eventBus: EventBus?
        let reviewDataContext: ReviewDataContext?
        /// When true, skip TakeoverIO prompt on pause and instead publish AgentPausedEvent to EventBus.
        let nonInteractivePause: Bool
        /// Called by RunOrchestrator to register a resume handle for a paused agent.
        /// Parameters: (pendingId, resumeClosure). The resumeClosure calls agent.resume(context:).
        let registerResumeHandle: (@Sendable (String, @Sendable @escaping (String) async -> Void) async -> Void)?
    }

    struct RunResult: Sendable {
        let totalSteps: Int
        let durationMs: Int
        let runSucceeded: Bool
        let externallyModified: Bool
        let takeoverEvent: RunMemoryProcessor.TakeoverEventContext?
        let runCompleteContext: RunCompleteContext?
        let responseText: String?
    }

    /// Executes the full agent pipeline: lock → trace → stream loop → cleanup → post-run.
    static func execute(
        buildResult: AgentBuildResult,
        runConfig: RunConfig
    ) async throws -> RunResult {
        let agent = buildResult.agent
        let runCompleteBox = buildResult.runCompleteBox
        let memoryDir = buildResult.memoryDir
        let memoryStore = buildResult.agentOptions.memoryStore as! FileBasedMemoryStore

        // Output handler
        let runMode = traceMode(fast: runConfig.fast, dryrun: runConfig.dryrun)
        let outputHandler: any SDKMessageOutputHandler = runConfig.json
            ? SDKJSONOutputHandler(mode: runMode)
            : SDKTerminalOutputHandler(mode: runMode)

        // TakeoverIO
        let takeoverIO: TakeoverIO
        if runConfig.json {
            takeoverIO = TakeoverIO(
                write: { fputs($0 + "\n", stderr); fflush(stderr) },
                readLine: { Swift.readLine() }
            )
        } else {
            takeoverIO = TakeoverIO()
        }

        let runId = generateRunId()
        outputHandler.displayRunStart(runId: runId, task: runConfig.task)

        // Desktop-level run lock
        let runLockService = RunLockService()
        if !runConfig.dryrun {
            let acquired = await runLockService.acquire(runId: runId)
            if !acquired {
                if let existingLock = await runLockService.readExistingLock() {
                    throw AxionError.runLocked(runId: existingLock.runId, pid: existingLock.pid)
                } else {
                    throw AxionError.runLocked(runId: "unknown", pid: 0)
                }
            }
        }

        // Trace recorder — SDK handles trace via AgentOptions.traceEnabled/traceBaseURL

        // Pre-run memory cleanup (fact demotion, expired entry removal)
        if !runConfig.noMemory {
            await RunMemoryProcessor.preRunCleanup(memoryStore: memoryStore, memoryDir: memoryDir)
        }

        // SIGINT handler
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        sigintSource.setEventHandler {
            agent.interrupt()
        }
        sigintSource.resume()

        // Stream loop state
        var totalSteps = 0
        var pendingLaunchAppToolUseIds: Set<String> = []
        let externallyModified = false
        var takeoverEvent: (issue: String, summary: String, feedback: String?, reason: String, duration: TimeInterval?)?
        var collectedMessages: [SDKMessage] = []
        var streamedMessages: [SDKMessage] = []

        // Pre-stream: set agent + orchestrator early so event handlers (ReviewScheduler)
        // can access them when AgentCompletedEvent arrives during stream completion.
        // Messages will be updated post-stream.
        runConfig.reviewDataContext?.update(
            agent: agent,
            messages: [],
            reviewOrchestrator: buildResult.reviewOrchestrator
        )

        let startTime = ContinuousClock.now

        // Stream loop
        await withTaskCancellationHandler {
            let messageStream = agent.stream(runConfig.task, eventBus: runConfig.eventBus)
            for await message in messageStream {
                if _Concurrency.Task.isCancelled { break }
                if case .toolUse = message { totalSteps += 1 }
                streamedMessages.append(message)
                outputHandler.handle(message)

                // Collect messages for post-run review
                switch message {
                case .userMessage, .assistant, .toolResult, .toolUse:
                    collectedMessages.append(message)
                default:
                    break
                }

                switch message {
                case .assistant:
                    break
                case .toolUse(let data):
                    if data.toolName.contains("launch_app") {
                        pendingLaunchAppToolUseIds.insert(data.toolUseId)
                    }
                    // Track Skill tool usage
                    if data.toolName == "Skill", let store = buildResult.usageStore {
                        let skillName = extractSkillName(from: data.input)
                        if let skillName {
                            do {
                                try await store.bumpView(skillName: skillName)
                            } catch {
                                axionSkillUsageLogger.warning("Skill usage tracking failed for '\(skillName)': \(error.localizedDescription)")
                            }
                        }
                    }
                case .toolResult(let data):
                    // Activate app after launch_app (must run from CLI process, not AxionHelper)
                    if pendingLaunchAppToolUseIds.remove(data.toolUseId) != nil {
                        if let bundleId = extractBundleIdFromLaunchResult(data.content) {
                            activateAppFromCLI(bundleId: bundleId)
                        }
                    }
                case .system(let data):
                    switch data.subtype {
                    case .paused:
                        guard let pausedData = data.pausedData else { break }
                        let pauseResult = await handlePausedEvent(
                            pausedData: pausedData,
                            agent: agent,
                            runConfig: runConfig,
                            takeoverIO: takeoverIO,
                            totalSteps: totalSteps
                        )
                        takeoverEvent = pauseResult.takeoverEvent
                    case .pausedTimeout:
                        takeoverIO.displayTimeoutPrompt()
                    default:
                        break
                    }
                case .result:
                    break
                default:
                    break
                }
            }
        } onCancel: {
            agent.interrupt()
        }

        // Post-stream: update messages (agent + orchestrator already set pre-stream)
        runConfig.reviewDataContext?.update(
            agent: agent,
            messages: collectedMessages,
            reviewOrchestrator: buildResult.reviewOrchestrator
        )

        let responseText = Self.collectVisibleResponseText(from: streamedMessages)

        let durationMs = durationToMs(ContinuousClock.now - startTime)

        // Cleanup
        try? await agent.close()
        sigintSource.cancel()
        signal(SIGINT, SIG_DFL)
        outputHandler.displayCompletion()

        // Post-run data from SDK's onRunComplete context
        let runCtx = runCompleteBox.context
        let runSucceeded = runCtx?.status == .success
        let takeoverContext: RunMemoryProcessor.TakeoverEventContext? = takeoverEvent.map { event in
            RunMemoryProcessor.TakeoverEventContext(
                issue: event.issue,
                summary: event.summary,
                feedback: event.feedback,
                reason: event.reason,
                duration: event.duration
            )
        }

        // Post-run review — after memory processing, before lock release
        await Self.executePostRunReview(
            buildResult: buildResult,
            runConfig: runConfig,
            runId: runId,
            collectedMessages: collectedMessages,
            agent: agent
        )

        // Post-run curator — after review, before lock release
        await Self.executePostRunCurator(
            buildResult: buildResult,
            runConfig: runConfig,
            runId: runId,
            agent: agent
        )

        // Lock release
        if !runConfig.dryrun {
            await runLockService.release()
        }

        return RunResult(
            totalSteps: totalSteps,
            durationMs: durationMs,
            runSucceeded: runSucceeded,
            externallyModified: externallyModified,
            takeoverEvent: takeoverContext,
            runCompleteContext: runCtx,
            responseText: responseText
        )
    }
}
