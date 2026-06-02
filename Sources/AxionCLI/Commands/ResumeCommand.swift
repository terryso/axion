import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

struct ResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a previous agent session"
    )

    nonisolated(unsafe) static var createRuntime: @Sendable (EventBus) -> any AxionRuntimeResuming = { AxionRuntime(eventBus: $0) }
    nonisolated(unsafe) static var notify: @Sendable (String, String?, String) -> Void = RunOrchestrator.sendDesktopNotification

    @Argument(help: "Session ID to resume")
    var sessionId: String

    @Flag(name: .long, help: "Fast mode: reduced max steps, simplified planning")
    var fast: Bool = false

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "JSON output")
    var json: Bool = false

    @Flag(name: .long, help: "Disable memory context injection")
    var noMemory: Bool = false

    @Flag(name: .long, help: "Disable visual delta check")
    var noVisualDelta: Bool = false

    @Flag(name: .long, help: "Disable post-run review")
    var noReview: Bool = false

    @Option(name: .long, help: "Max steps")
    var maxSteps: Int?

    mutating func run() async throws {
        let config = try await ConfigManager.loadConfig()

        let effectiveMaxSteps = RunOrchestrator.computeEffectiveMaxSteps(
            fast: fast, maxSteps: maxSteps, configMaxSteps: config.maxSteps
        )
        let effectiveMaxTokens = RunOrchestrator.computeEffectiveMaxTokens(fast: fast)

        let eventBus = EventBus()
        let runtime = Self.createRuntime(eventBus)
        let reviewDC = await registerHandlers(into: runtime, config: config)

        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "Continue the previous task.",
            noMemory: noMemory,
            maxSteps: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens,
            verbose: verbose,
            fast: fast
        )

        let overrides = AxionRuntime.RunOverrides(
            json: json,
            noVisualDelta: noVisualDelta,
            noReview: noReview,
            onReviewCompleted: nil,
            reviewDataContext: reviewDC,
            nonInteractivePause: false, registerResumeHandle: nil
        )

        let result: AxionRunResult
        do {
            result = try await runtime.resumeSession(sessionId, buildConfig: buildConfig, runOverrides: overrides)
        } catch {
            eventLoopTask.cancel()
            await runtime.stopEventLoop()
            throw error
        }
        eventLoopTask.cancel()
        await runtime.stopEventLoop()

        if !json {
            let elapsedSec = result.durationMs / 1000
            let numTurns = result.runCompleteContext?.numTurns ?? result.totalSteps
            let title = result.state == .completed ? "Axion 完成" : "Axion 失败"
            var subtitle = "耗时 \(elapsedSec)s · \(numTurns) 次调用"
            if let cost = result.runCompleteContext?.totalCostUsd, cost > 0 {
                subtitle += " · $\(String(format: "%.4f", cost))"
            }
            Self.notify(
                title,
                subtitle,
                "Session \(sessionId) 已恢复"
            )
        }

        if result.state == .failed {
            throw ExitCode(1)
        }
    }

    @discardableResult
    private func registerHandlers(into runtime: any AxionRuntimeResuming, config: AxionConfig) async -> ReviewDataContext {
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let traceDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("runs")
        let reviewDataContext = ReviewDataContext()

        let profile = HandlerProfile(
            context: .cli,
            config: config,
            memoryDir: memoryDir,
            traceDir: traceDir,
            noMemory: noMemory,
            noReview: noReview,
            noVisualDelta: noVisualDelta,
            reviewDataContext: reviewDataContext
        )
        for handler in profile.buildHandlers() {
            await runtime.registerHandler(handler)
        }
        return reviewDataContext
    }
}
