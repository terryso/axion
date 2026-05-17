import ArgumentParser
import AxionCore
import Foundation

struct RecordedSkillRunner {

    static func run(
        skill: Skill,
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
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                encoder.dateEncodingStrategy = .iso8601
                let updatedData = try encoder.encode(updatedSkill)
                try updatedData.write(to: URL(fileURLWithPath: skillPath))
            } catch {
                fputs("[axion] warning: skill metadata update failed: \(error.localizedDescription)\n", stderr)
            }
        } else if let error = result.errorMessage {
            print("技能 '\(skill.name)' \(error)。建议使用 axion run 代替。")
            throw ExitCode(1)
        }
    }
}
