import ArgumentParser
import AxionCore
import OpenAgentSDK

struct SkillListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "列出所有已保存的技能"
    )

    func run() async throws {
        // Recorded skills (from JSON files)
        let recordedOutput = Self.listSkills(in: ConfigManager.skillsDirectory)

        // Prompt skills (from SkillRegistry including built-in)
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        registry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)
        let promptOutput = Self.listPromptSkills(from: registry)

        if recordedOutput.contains("无已保存的技能") && promptOutput.isEmpty {
            print("无已保存的技能。使用 axion skill compile <name> 创建技能。")
        } else {
            if !recordedOutput.contains("无已保存的技能") {
                print(recordedOutput)
            }
            if !promptOutput.isEmpty {
                print(promptOutput)
            }
        }
    }

    // MARK: - Recorded Skills (JSON files)

    static func listSkills(in directory: String) -> String {
        let skills = loadAllRecordedSkills(in: directory)

        guard !skills.isEmpty else {
            return "无已保存的技能。使用 axion skill compile <name> 创建技能。"
        }

        var lines: [String] = ["已保存的技能:"]

        for (name, skill) in skills {
            lines.append("  \(name)")
            lines.append("    描述: \(skill.description)")
            lines.append("    类型: recorded")
            if !skill.parameters.isEmpty {
                let paramDescs = skill.parameters.map { p in
                    let defaultStr = p.defaultValue ?? "无"
                    return "\(p.name) (默认值: \(defaultStr))"
                }
                lines.append("    参数: \(paramDescs.joined(separator: ", "))")
            }
            let lastUsedStr = skill.lastUsedAt.map { axionDateTimeFormatter.string(from: $0) } ?? "从未使用"
            lines.append("    执行次数: \(skill.executionCount), 上次使用: \(lastUsedStr)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt Skills (from SkillRegistry)

    static func listPromptSkills(from registry: SkillRegistry) -> String {
        let allSkills = registry.allSkills.filter { $0.userInvocable }
        guard !allSkills.isEmpty else { return "" }

        var lines: [String] = ["Prompt 技能:"]

        for skill in allSkills.sorted(by: { $0.name < $1.name }) {
            lines.append("  \(skill.name)")
            lines.append("    描述: \(skill.description)")
            lines.append("    类型: prompt")
            let source = skill.baseDir != nil ? "filesystem" : "built-in"
            lines.append("    来源: \(source)")
            if !skill.aliases.isEmpty {
                lines.append("    别名: \(skill.aliases.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }
}
