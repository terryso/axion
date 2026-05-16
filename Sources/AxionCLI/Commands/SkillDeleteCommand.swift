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
        let safeName = RecordCommand.sanitizeFileName(name)
        let skillsDir = SkillCompileCommand.skillsDirectory()
        let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

        guard FileManager.default.fileExists(atPath: skillPath) else {
            throw ValidationError("技能不存在: \(safeName)")
        }

        do {
            try FileManager.default.removeItem(atPath: skillPath)
        } catch {
            throw ValidationError("删除技能失败: \(error.localizedDescription)")
        }

        print("技能 '\(safeName)' 已删除。")
    }
}
