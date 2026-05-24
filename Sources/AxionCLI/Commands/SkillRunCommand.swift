import ArgumentParser
import AxionCore
import Foundation
import os
import OpenAgentSDK

struct SkillRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行已保存的技能"
    )

    @Argument(help: "技能名称")
    var name: String

    @Option(name: .long, help: "参数（可重复，格式 key=value）")
    var param: [String] = []

    @Flag(name: .long, help: "允许前台操作")
    var allowForeground: Bool = false

    mutating func run() async throws {
        let safeName = RecordCommand.sanitizeFileName(name)
        let skillsDir = SkillCompileCommand.skillsDirectory()
        let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

        guard FileManager.default.fileExists(atPath: skillPath) else {
            throw ValidationError("技能不存在: \(safeName)")
        }

        let skillData = try Data(contentsOf: URL(fileURLWithPath: skillPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let skill: AxionCore.Skill
        do {
            skill = try decoder.decode(Skill.self, from: skillData)
        } catch {
            throw ValidationError("无法解析技能文件: \(error.localizedDescription)")
        }

        let paramValues = try parseParams()

        for param in skill.parameters where param.defaultValue == nil {
            guard paramValues[param.name] != nil else {
                throw ValidationError("缺少必需参数: \(param.name)")
            }
        }

        try await RecordedSkillRunner.run(
            skill: skill,
            skillPath: skillPath,
            paramValues: paramValues
        )

        // Track skill usage
        let usageStore = SkillUsageStore(skillsDir: skillsDir)
        do {
            try await usageStore.bumpView(skillName: skill.name)
        } catch {
            let logger = Logger(subsystem: "com.axion.cli", category: "SkillUsage")
            logger.warning("Skill usage tracking failed for '\(skill.name)': \(error.localizedDescription)")
        }
    }

    private func parseParams() throws -> [String: String] {
        try Self.parseParamStrings(param)
    }

    static func parseParamStrings(_ strings: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for p in strings {
            guard let eqIndex = p.firstIndex(of: "=") else {
                throw ValidationError("参数格式错误: \(p)。正确格式: key=value")
            }
            let key = String(p[..<eqIndex])
            let value = String(p[p.index(after: eqIndex)...])
            guard !key.isEmpty else {
                throw ValidationError("参数名不能为空: \(p)")
            }
            result[key] = value
        }
        return result
    }
}
