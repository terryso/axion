import Foundation
import Testing

@testable import AxionCLI

@Suite("SlashCommand Metadata (AC4)")
struct SlashCommandMetadataTests {

    // MARK: - aliases

    @Test("/exit aliases == [quit]")
    func exitAliases() {
        #expect(SlashCommand.exit.aliases == ["quit"])
    }

    @Test("非 exit 命令 aliases 为空")
    func nonExitAliasesEmpty() {
        for cmd in SlashCommand.allCases where cmd != .exit {
            #expect(cmd.aliases.isEmpty, "\(cmd.rawValue) should have no aliases")
        }
    }

    // MARK: - acceptsArgs

    @Test("/model acceptsArgs == true")
    func modelAcceptsArgs() {
        #expect(SlashCommand.model.acceptsArgs == true)
    }

    @Test("/resume acceptsArgs == true")
    func resumeAcceptsArgs() {
        #expect(SlashCommand.resume.acceptsArgs == true)
    }

    @Test("/storage acceptsArgs == true")
    func storageAcceptsArgs() {
        #expect(SlashCommand.storage.acceptsArgs == true)
    }

    @Test("其他命令 acceptsArgs == false")
    func otherCommandsNoArgs() {
        let noArgCommands: [SlashCommand] = [.help, .clear, .compact, .cost, .config, .exit, .newSession, .fork, .archive]
        for cmd in noArgCommands {
            #expect(cmd.acceptsArgs == false, "\(cmd.rawValue) should not accept args")
        }
    }

    // MARK: - availableDuringTask

    @Test("/resume /new /fork /archive availableDuringTask == false")
    func structuralCommandsNotAvailableDuringTask() {
        let notAvailable: [SlashCommand] = [.resume, .newSession, .fork, .archive, .apps, .storage]
        for cmd in notAvailable {
            #expect(cmd.availableDuringTask == false, "\(cmd.rawValue) should not be available during task")
        }
    }

    @Test("help/cost/config/clear/exit availableDuringTask == true")
    func coreCommandsAvailableDuringTask() {
        let available: [SlashCommand] = [.help, .cost, .config, .clear, .exit]
        for cmd in available {
            #expect(cmd.availableDuringTask == true, "\(cmd.rawValue) should be available during task")
        }
    }

    @Test("compact/model availableDuringTask == true (默认)")
    func defaultAvailableDuringTask() {
        #expect(SlashCommand.compact.availableDuringTask == true)
        #expect(SlashCommand.model.availableDuringTask == true)
    }

    // MARK: - availableInSide

    @Test("所有命令 availableInSide == true")
    func allAvailableInSide() {
        for cmd in SlashCommand.allCases {
            #expect(cmd.availableInSide == true, "\(cmd.rawValue) should be available in side session")
        }
    }

    // MARK: - allNames

    @Test("/exit allNames == [/exit, /quit]")
    func exitAllNames() {
        #expect(SlashCommand.exit.allNames == ["/exit", "/quit"])
    }

    @Test("/help allNames == [/help]")
    func helpAllNames() {
        #expect(SlashCommand.help.allNames == ["/help"])
    }

    @Test("无别名命令 allNames 只含 rawValue")
    func noAliasCommandsAllNames() {
        let singleNameCommands: [SlashCommand] = [.help, .clear, .compact, .model, .cost, .resume, .config, .newSession, .fork, .archive, .apps, .storage]
        for cmd in singleNameCommands {
            #expect(cmd.allNames == [cmd.rawValue], "\(cmd.rawValue) allNames should be just [rawValue]")
        }
    }
}
