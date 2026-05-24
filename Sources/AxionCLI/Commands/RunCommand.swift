import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

/// Main entry point for `axion run` — thin CLI layer that parses arguments
/// and delegates execution to RunOrchestrator.
///
/// **Design Decisions:**
/// - **Thin CLI layer**: argument parsing lives here; all execution logic
///   (stream loop, lock, trace, takeover, memory processing) lives in RunOrchestrator.
/// - **Skill detection before agent build**: explicit skill invocations (`/skill-name ...`)
///   bypass the full agent build to save one LLM round trip.
/// - **Layered configuration** (defaults → config.json → env vars → CLI args): see `ConfigManager.loadConfig`.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行桌面自动化任务"
    )

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

        // Skill direct execution path: bypasses full agent build
        if !noSkills, let skillName = RunOrchestrator.parseSkillName(from: task) {
            let registry = SkillRegistry()
            AxionBuiltInSkills.registerAll(into: registry)
            _ = registry.registerDiscoveredSkills()
            if let skill = registry.find(skillName) {
                fputs("[axion] 已加载 \(registry.allSkills.count) 个技能\n", stderr)
                try await RunOrchestrator.executeSkillDirectly(
                    skill: skill, task: task, config: config,
                    json: json, fast: fast, verbose: verbose
                )
                return
            }
        }

        // Standard agent execution path
        let effectiveMaxSteps = RunOrchestrator.computeEffectiveMaxSteps(
            fast: fast, maxSteps: maxSteps, configMaxSteps: config.maxSteps
        )
        let effectiveMaxTokens = RunOrchestrator.computeEffectiveMaxTokens(fast: fast)

        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config, task: task, noMemory: noMemory, noSkills: noSkills,
            allowForeground: allowForeground, maxSteps: effectiveMaxSteps,
            maxTokens: effectiveMaxTokens, verbose: verbose, dryrun: dryrun, fast: fast
        )

        let buildResult = try await AgentBuilder.build(buildConfig)

        if buildResult.skillRegisteredCount > 0 {
            fputs("[axion] 已加载 \(buildResult.skillRegisteredCount) 个技能\n", stderr)
        }

        _ = try await RunOrchestrator.execute(
            buildResult: buildResult,
            runConfig: RunOrchestrator.RunConfig(
                task: task, fast: fast, dryrun: dryrun, json: json,
                noMemory: noMemory, noVisualDelta: noVisualDelta,
                allowForeground: allowForeground, maxSteps: maxSteps, config: config,
                noReview: noReview
            )
        )
    }
}
