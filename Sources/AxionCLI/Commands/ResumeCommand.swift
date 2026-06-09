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

        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "Continue the previous task.",
            noMemory: noMemory,
            maxSteps: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens,
            verbose: verbose,
            fast: fast
        )

        let result = try await executeWithRuntime(config: config) { runtime, overrides in
            try await runtime.resumeSession(sessionId, buildConfig: buildConfig, runOverrides: overrides)
        }
        try handleResult(result)
    }

    // MARK: - Runtime Lifecycle

    private func executeWithRuntime(
        config: AxionConfig,
        execute: (any AxionRuntimeResuming, AxionRuntime.RunOverrides) async throws -> AxionRunResult
    ) async throws -> AxionRunResult {
        let eventBus = EventBus()
        let runtime = Self.createRuntime(eventBus)
        return try await executeCLIWithRuntime(
            config: config, json: json,
            noMemory: noMemory, noReview: noReview, noVisualDelta: noVisualDelta,
            runtime: runtime
        ) { overrides in
            try await execute(runtime, overrides)
        }
    }

    private func handleResult(_ result: AxionRunResult) throws {
        if !json {
            sendRunCompletionNotification(
                result: result,
                message: "Session \(sessionId) 已恢复",
                notify: Self.notify
            )
        }
        if outputCLIError(result, json: json) {
            throw ExitCode(1)
        }
    }
}
