import ArgumentParser
import Foundation

struct SkillDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "删除已保存的技能"
    )

    @Argument(help: "技能名称")
    var name: String

    func run() throws {
        let skillPath = resolveFilePath(name: name, in: ConfigManager.skillsDirectory)

        guard FileManager.default.fileExists(atPath: skillPath) else {
            throw ValidationError("技能不存在: \(name)")
        }

        do {
            try FileManager.default.removeItem(atPath: skillPath)
        } catch {
            throw ValidationError("删除技能失败: \(error.localizedDescription)")
        }

        print("技能 '\(name)' 已删除。")
    }
}
