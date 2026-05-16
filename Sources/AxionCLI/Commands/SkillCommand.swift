import ArgumentParser
import Foundation

/// Parent command group for `axion skill` subcommands.
struct SkillCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "管理可复用技能",
        subcommands: [SkillCompileCommand.self, SkillRunCommand.self, SkillListCommand.self, SkillDeleteCommand.self]
    )
}
