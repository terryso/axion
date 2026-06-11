import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

/// Main entry point for `axion run` — thin CLI layer that parses arguments
/// and delegates execution to AxionRuntime.
///
/// **Design Decisions:**
/// - **Thin CLI layer**: argument parsing lives here; all execution logic
///   (stream loop, lock, trace, takeover, memory processing) lives in AxionRuntime.
/// - **Skill detection before agent build**: explicit skill invocations (`/skill-name ...`)
///   bypass the full agent build to save one LLM round trip.
/// - **Layered configuration** (defaults → config.json → env vars → CLI args): see `ConfigManager.loadConfig`.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行桌面自动化任务"
    )

    // Test seams — overridden in unit tests to inject mocks.
    nonisolated(unsafe) static var createRuntime: @Sendable (EventBus) -> any AxionRuntimeRunning = { AxionRuntime(eventBus: $0) }
    nonisolated(unsafe) static var skillExecutorOverride: (@Sendable (String, AxionConfig, Bool, Bool, Bool) async throws -> Void)?
    nonisolated(unsafe) static var notify: @Sendable (String, String?, String) -> Void = RunOrchestrator.sendDesktopNotification

    @Argument(help: "任务描述")
    var task: String

    @Flag(name: .long, help: "干跑模式（仅生成计划不实际执行）")
    var dryrun: Bool = false

    @Option(name: .long, help: "单次运行最大步骤数")
    var maxSteps: Int?

    @Option(name: .long, help: "最大批次")
    var maxBatches: Int?

    @Flag(name: .long, help: "允许前台操作")
    var allowForeground: Bool = false

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    @Flag(name: .long, help: "JSON 格式输出")
    var json: Bool = false

    @Flag(name: .long, help: "禁用 Memory 上下文注入")
    var noMemory: Bool = false

    @Flag(name: .long, help: "快速模式：简化规划，减少 LLM 调用")
    var fast: Bool = false

    @Flag(name: .long, help: "禁用视觉增量检查")
    var noVisualDelta: Bool = false

    @Flag(name: .long, help: "禁用技能系统")
    var noSkills: Bool = false

    @Option(name: .long, help: "最大 LLM 调用次数")
    var maxModelCalls: Int?

    @Option(name: .long, help: "最大截图次数")
    var maxScreenshots: Int?

    @Flag(name: .long, help: "禁用 post-run review 和 curator")
    var noReview: Bool = false

    @Option(name: .long, help: "覆盖 review agent 使用的模型")
    var reviewModel: String?

    mutating func run() async throws {
        let cliOverrides = CLIOverrides(
            maxSteps: maxSteps,
            maxBatches: maxBatches,
            maxModelCalls: maxModelCalls,
            maxScreenshots: maxScreenshots,
            reviewModel: reviewModel
        )
        let config = try await ConfigManager.loadConfig(cliOverrides: cliOverrides)

        // Skill direct execution path: route through AxionRuntime
        if !noSkills, let skillName = RunOrchestrator.parseSkillName(from: task) {
            let registry = SkillRegistry()
            AxionBuiltInSkills.registerAll(into: registry)
            _ = registry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)
            if let skill = registry.find(skillName) {
                fputs("[axion] 已加载 \(registry.allSkills.count) 个技能\n", stderr)
                if let override = Self.skillExecutorOverride {
                    try await override(task, config, json, fast, verbose)
                } else {
                    let effectiveMaxSteps = RunOrchestrator.computeEffectiveMaxSteps(
                        fast: fast, maxSteps: maxSteps, configMaxSteps: config.maxSteps
                    )
                    let skillBuildConfig = AgentBuilder.BuildConfig.forSkillExecution(
                        config: config,
                        skill: skill,
                        maxSteps: effectiveMaxSteps,
                        verbose: verbose
                    )
                    let result = try await executeWithRuntime(config: config) { runtime, overrides in
                        try await runtime.executeSkill(
                            skill: skill,
                            task: task,
                            config: config,
                            buildConfig: skillBuildConfig,
                            runOverrides: overrides
                        )
                    }
                    try handleResult(result)
                }
                return
            }
        }

        // AxionRuntime execution path
        let effectiveMaxSteps = RunOrchestrator.computeEffectiveMaxSteps(
            fast: fast, maxSteps: maxSteps, configMaxSteps: config.maxSteps
        )
        let effectiveMaxTokens = RunOrchestrator.computeEffectiveMaxTokens(fast: fast)

        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config, task: task, noMemory: noMemory, noSkills: noSkills,
            allowForeground: allowForeground, maxSteps: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens, verbose: verbose, dryrun: dryrun, fast: fast,
            json: json
        )

        let result = try await executeWithRuntime(config: config) { runtime, overrides in
            try await runtime.execute(buildConfig: buildConfig, runOverrides: overrides, sessionId: nil)
        }
        try handleResult(result)
    }

    // MARK: - Runtime Lifecycle

    private func executeWithRuntime(
        config: AxionConfig,
        execute: (any AxionRuntimeRunning, AxionRuntime.RunOverrides) async throws -> AxionRunResult
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
            sendCompletionNotification(result: result)
        }
        if outputCLIError(result, json: json) {
            throw ExitCode(1)
        }
    }

    // MARK: - Completion Notification

    private func sendCompletionNotification(result: AxionRunResult) {
        let summary = extractSummaryLine(from: result.responseText ?? result.task)
        sendRunCompletionNotification(result: result, message: summary, notify: Self.notify)
    }

    private func extractSummaryLine(from text: String) -> String {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        if let resultLine = lines.last(where: { $0.hasPrefix("[结果]") }) {
            return String(resultLine.dropFirst("[结果]".count).trimmingCharacters(in: .whitespaces))
        }
        return lines.last ?? text
    }
}
