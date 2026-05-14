import ArgumentParser
import AxionCore
import Foundation

struct SkillListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "列出所有已保存的技能"
    )

    func run() async throws {
        let output = Self.listSkills(in: SkillCompileCommand.skillsDirectory())
        print(output)
    }

    // MARK: - Public Static API (for testing)

    static func listSkills(in directory: String) -> String {
        let fm = FileManager.default

        var fileNames: [String]
        do {
            fileNames = try fm.contentsOfDirectory(atPath: directory)
        } catch {
            return "无已保存的技能。使用 axion skill compile <name> 创建技能。"
        }

        let jsonFiles = fileNames.filter { $0.hasSuffix(".json") }

        guard !jsonFiles.isEmpty else {
            return "无已保存的技能。使用 axion skill compile <name> 创建技能。"
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var skills: [(name: String, skill: Skill)] = []
        for fileName in jsonFiles {
            let filePath = (directory as NSString).appendingPathComponent(fileName)
            guard let data = fm.contents(atPath: filePath) else { continue }
            guard let skill = try? decoder.decode(Skill.self, from: data) else { continue }
            skills.append((name: String(fileName.dropLast(5)), skill: skill))
        }

        guard !skills.isEmpty else {
            return "无已保存的技能。使用 axion skill compile <name> 创建技能。"
        }

        var lines: [String] = ["已保存的技能:"]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        for (name, skill) in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("  \(name)")
            lines.append("    描述: \(skill.description)")
            if !skill.parameters.isEmpty {
                let paramDescs = skill.parameters.map { p in
                    let defaultStr = p.defaultValue ?? "无"
                    return "\(p.name) (默认值: \(defaultStr))"
                }
                lines.append("    参数: \(paramDescs.joined(separator: ", "))")
            }
            let lastUsedStr = skill.lastUsedAt.map { dateFormatter.string(from: $0) } ?? "从未使用"
            lines.append("    执行次数: \(skill.executionCount), 上次使用: \(lastUsedStr)")
        }

        return lines.joined(separator: "\n")
    }
}
