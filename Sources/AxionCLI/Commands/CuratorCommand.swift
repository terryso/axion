import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

struct CuratorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "curator",
        abstract: "管理技能策展",
        subcommands: [CuratorRunCommand.self, CuratorStatusCommand.self]
    )
}

struct CuratorRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "立即执行策展（忽略间隔检查）"
    )

    @Flag(name: .long, help: "干跑模式（不实际修改）")
    var dryRun: Bool = false

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    mutating func run() async throws {
        let config = try await ConfigManager.loadConfig()

        let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")

        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        let curatorStore = SkillCuratorStore(skillsDir: skillsDir)
        let factStore = FactStore(memoryDir: memoryDir)
        let skillRegistry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: skillRegistry)
        _ = skillRegistry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)

        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AxionError.configError(reason: "API Key 未配置")
        }

        let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: config.baseURL)
        let evolutionModel = config.reviewModel ?? AxionConfig.defaultReviewModel
        let skillEvolver = LLMSkillEvolver(client: evolverClient, evolutionModel: evolutionModel)

        let curatorConfig = SkillCuratorConfig(
            intervalHours: config.curatorIntervalHours ?? 168.0,
            staleAfterDays: config.curatorStaleAfterDays ?? 30,
            archiveAfterDays: config.curatorArchiveAfterDays ?? 90,
            dryRun: dryRun,
            enabled: true
        )
        let skillCurator = SkillCurator(
            usageStore: usageStore,
            curatorStore: curatorStore,
            config: curatorConfig
        )
        let curator = IntelligentCurator(
            skillCurator: skillCurator,
            factStore: factStore,
            skillRegistry: skillRegistry,
            skillEvolver: skillEvolver,
            usageStore: usageStore,
            curatorStore: curatorStore,
            skillsDir: skillsDir
        )

        let buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config,
            task: "curator background task",
            noMemory: false,
            verbose: verbose,
            dryrun: false
        )
        let buildResult = try await AgentBuilder.build(buildConfig)
        let agent = buildResult.agent

        // Force-run: reset lastRunAt so Phase 1 (mechanical curation) also runs
        // regardless of interval. Without this, skillCurator.run() would skip
        // if the configured interval hasn't elapsed since the last automatic run.
        // Save original state so we can rollback on failure.
        let originalState = await curatorStore.loadState()
        var forceState = originalState
        forceState.lastRunAt = nil
        try await curatorStore.saveState(forceState)

        fputs("[axion] 正在执行策展...\n", stderr)
        let result: IntelligentCuratorResult
        do {
            result = try await curator.execute(parentAgent: agent, dryRun: dryRun)
        } catch {
            try? await curatorStore.saveState(originalState)
            try? await agent.close()
            throw error
        }

        let report = CuratorRunReport(from: result)
        fputs(report.renderMarkdown(), stderr)
        fputs("\n[axion] 策展完成，耗时 \(result.durationMs)ms\n", stderr)

        try? await agent.close()
    }
}

struct CuratorStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "显示策展状态和配置"
    )

    func run() async throws {
        let config = try await ConfigManager.loadConfig()

        let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
        let curatorStore = SkillCuratorStore(skillsDir: skillsDir)
        let state = await curatorStore.loadState()

        let intervalHours = config.curatorIntervalHours ?? 168.0
        let curatorEnabled = config.curatorEnabled ?? true

        fputs("策展状态:\n", stdout)
        fputs("  启用: \(curatorEnabled ? "是" : "否")\n", stdout)
        fputs("  间隔: \(intervalHours) 小时\n", stdout)

        if let lastRun = state.lastRunAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            fputs("  上次策展: \(formatter.string(from: lastRun))\n", stdout)

            let nextRun = lastRun.addingTimeInterval(intervalHours * 3600)
            let remaining = nextRun.timeIntervalSinceNow
            if remaining > 0 {
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                fputs("  下次策展: \(formatter.string(from: nextRun)) (剩余 \(hours)h \(minutes)m)\n", stdout)
            } else {
                fputs("  下次策展: 即可执行（已过间隔）\n", stdout)
            }
        } else {
            fputs("  上次策展: 未执行过\n", stdout)
            fputs("  下次策展: 即可执行\n", stdout)
        }

        fputs("  运行次数: \(state.runCount)\n", stdout)

        let reviewModel = config.reviewModel ?? "继承 parent agent"
        fputs("  Review 模型: \(reviewModel)\n", stdout)
        fputs("  干跑模式: \(config.curatorDryRun ?? false ? "是" : "否")\n", stdout)
        let minIdleHours = 2.0  // SDK default for SkillCuratorConfig.minIdleHours
        fputs("  最小空闲时间: \(Int(minIdleHours)) 小时\n", stdout)
        fputs("  过期天数: \(config.curatorStaleAfterDays ?? 30)\n", stdout)
        fputs("  归档天数: \(config.curatorArchiveAfterDays ?? 90)\n", stdout)
    }
}
