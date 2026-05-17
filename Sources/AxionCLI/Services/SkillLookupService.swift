import AxionCore
import Foundation
import OpenAgentSDK

enum SkillLookupResult: Sendable {
    case promptSkill(OpenAgentSDK.Skill)
    case recordedSkill(AxionCore.Skill, path: String)
    case notFound
}

struct SkillLookupService: Sendable {

    let registry: SkillRegistry
    let skillsDirectory: String

    init(registry: SkillRegistry, skillsDirectory: String? = nil) {
        self.registry = registry
        self.skillsDirectory = skillsDirectory ?? SkillCompileCommand.skillsDirectory()
    }

    func lookup(name: String) -> SkillLookupResult {
        // Track 1: prompt skill via SkillRegistry
        if let promptSkill = registry.find(name) {
            return .promptSkill(promptSkill)
        }

        // Track 2: recorded skill from JSON file
        let safeName = RecordCommand.sanitizeFileName(name)
        let skillPath = (skillsDirectory as NSString).appendingPathComponent("\(safeName).json")

        guard FileManager.default.fileExists(atPath: skillPath) else {
            return .notFound
        }

        do {
            let skillData = try Data(contentsOf: URL(fileURLWithPath: skillPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let skill = try decoder.decode(AxionCore.Skill.self, from: skillData)
            return .recordedSkill(skill, path: skillPath)
        } catch {
            return .notFound
        }
    }

    /// Parse a `/skill-name` prefixed task string into (skillName, remainingArgs).
    /// Returns nil if the string does not start with `/` or is just `/`.
    static func parseSkillInvocation(_ task: String) -> (name: String, args: String?)? {
        guard task.hasPrefix("/") else { return nil }
        let withoutSlash = String(task.dropFirst())
        guard !withoutSlash.isEmpty else { return nil }

        let parts = withoutSlash.split(separator: " ", maxSplits: 1)
        let name = String(parts[0])
        guard !name.isEmpty else { return nil }

        let args = parts.count > 1 ? String(parts[1]) : nil
        return (name, args)
    }
}
