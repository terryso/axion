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
            _ = registry.registerDiscoveredSkills()
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

                    let eventBus = EventBus()
                    let runtime = Self.createRuntime(eventBus)
                    let reviewDC = await registerHandlers(into: runtime, config: config)

                    let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

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
                        result = try await runtime.executeSkill(
                            skill: skill,
                            task: task,
                            config: config,
                            buildConfig: skillBuildConfig,
                            runOverrides: overrides
                        )
                    } catch {
                        eventLoopTask.cancel()
                        await runtime.stopEventLoop()
                        throw error
                    }
                    eventLoopTask.cancel()
                    await runtime.stopEventLoop()

                    if !json {
                        sendCompletionNotification(result: result)
                    }

                    if result.state == .failed {
                        if let msg = result.errorMessage {
                            fputs("[axion] 错误: \(msg)\n", stderr)
                        }
                        throw ExitCode(1)
                    }
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
            maxTokens: effectiveMaxTokens, verbose: verbose, dryrun: dryrun, fast: fast
        )

        let eventBus = EventBus()
        let runtime = Self.createRuntime(eventBus)
        let reviewDC = await registerHandlers(into: runtime, config: config)

        // Start event loop concurrently so handlers receive events during execution
        let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

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
            result = try await runtime.execute(buildConfig: buildConfig, runOverrides: overrides, sessionId: nil)
        } catch {
            eventLoopTask.cancel()
            await runtime.stopEventLoop()
            throw error
        }
        eventLoopTask.cancel()
        await runtime.stopEventLoop()

        if !json {
            sendCompletionNotification(result: result)
        }

        if result.state == .failed {
            if let msg = result.errorMessage {
                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    let obj: [String: String] = ["error": msg, "runId": result.sessionId, "status": "failed"]
                    if let data = try? encoder.encode(obj) {
                        fputs(String(data: data, encoding: .utf8) ?? "{}\n", stdout)
                    }
                } else {
                    fputs("[axion] 错误: \(msg)\n", stderr)
                }
            }
            throw ExitCode(1)
        }
    }

    @discardableResult
    private func registerHandlers(into runtime: any AxionRuntimeRunning, config: AxionConfig) async -> ReviewDataContext {
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

    private func sendCompletionNotification(result: AxionRunResult) {
        let elapsedSec = result.durationMs / 1000
        let numTurns = result.runCompleteContext?.numTurns ?? result.totalSteps

        let summary = extractSummaryLine(from: result.responseText ?? result.task)

        let title: String
        switch result.state {
        case .completed: title = "Axion 完成"
        case .failed: title = "Axion 失败"
        default: title = "Axion"
        }

        var subtitle = "耗时 \(elapsedSec)s · \(numTurns) 次调用"
        if let cost = result.runCompleteContext?.totalCostUsd, cost > 0 {
            subtitle += " · $\(String(format: "%.4f", cost))"
        }

        Self.notify(
            title,
            subtitle,
            String(summary.prefix(200))
        )
    }

    private func extractSummaryLine(from text: String) -> String {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        if let resultLine = lines.last(where: { $0.hasPrefix("[结果]") }) {
            return String(resultLine.dropFirst("[结果]".count).trimmingCharacters(in: .whitespaces))
        }
        return lines.last ?? text
    }
}
