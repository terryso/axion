import ArgumentParser
import AxionCore
import Foundation
import OpenAgentSDK

struct RecordedSkillRunner {

    static func run(
        skill: AxionCore.Skill,
        skillPath: String,
        paramValues: [String: String]
    ) async throws {
        // Validate required parameters and fill defaults before starting helper
        var resolvedParams = paramValues
        for param in skill.parameters {
            if resolvedParams[param.name] == nil, let defaultVal = param.defaultValue {
                resolvedParams[param.name] = defaultVal
            }
        }
        let requiredParams = skill.parameters.filter { $0.defaultValue == nil }
        let missingParams = requiredParams.filter { resolvedParams[$0.name] == nil }
        if !missingParams.isEmpty {
            let names = missingParams.map(\.name).joined(separator: ", ")
            fputs("技能 '\(skill.name)' 缺少必需参数: \(names)\n", stderr)
            throw ExitCode(1)
        }

        let helperManager = HelperProcessManager()
        print("[axion] 正在启动 Helper...")
        try await helperManager.start()

        let result: SkillExecutionResult
        do {
            let client = HelperMCPClientAdapter(manager: helperManager)
            let executor = SkillExecutor(client: client)
            result = try await executor.execute(skill: skill, paramValues: resolvedParams)
        } catch {
            await helperManager.stop()
            throw error
        }

        await helperManager.stop()

        if result.success {
            let formatted = String(format: "%.1f", result.durationSeconds)
            print("技能 '\(skill.name)' 完成。\(result.stepsExecuted) 步，耗时 \(formatted) 秒。")

            do {
                var updatedSkill = skill
                updatedSkill.lastUsedAt = Date()
                updatedSkill.executionCount += 1
                let updatedData = try axionPersistentEncoder.encode(updatedSkill)
                try updatedData.write(to: URL(fileURLWithPath: skillPath))
            } catch {
                fputs("[axion] warning: skill metadata update failed: \(error.localizedDescription)\n", stderr)
            }

            // Record skill execution Memory (Story 18.2 AC5)
            recordSkillMemory(
                skillName: skill.name,
                kind: .affordance,
                description: "Recorded skill '\(skill.name)' executed successfully, \(result.stepsExecuted) steps",
                confidence: 0.7
            )
        } else if let error = result.errorMessage {
            // Record failure Memory (Story 18.2 AC5 — avoid kind on error)
            recordSkillMemory(
                skillName: skill.name,
                kind: .avoid,
                description: "Recorded skill '\(skill.name)' failed: \(error)",
                confidence: 0.6
            )

            print("技能 '\(skill.name)' \(error)。建议使用 axion run 代替。")
            throw ExitCode(1)
        }
    }

    // MARK: - Skill Memory Recording

    private static func recordSkillMemory(
        skillName: String,
        kind: MemoryKind,
        description: String,
        confidence: Double
    ) {
        _Concurrency.Task {
            do {
                let factStore = AxionFactStore(memoryDir: ConfigManager.memoryDirectory)
                let lifecycleService = OpenAgentSDK.MemoryLifecycleService()

                let fact = AppMemoryFact.create(
                    domain: "unknown",
                    kind: kind,
                    description: description,
                    confidence: confidence,
                    scope: "skill:\(skillName)"
                )
                try await AppMemoryFact.mergeAndPersist(
                    fact: fact,
                    into: factStore,
                    lifecycleService: lifecycleService
                )
            } catch {
                fputs("[axion] warning: skill memory record failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }
}
