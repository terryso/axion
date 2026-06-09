import Foundation
import Testing

@testable import AxionCLI

@Suite("SlashCommand New Commands (38.7)")
struct SlashCommandNewTests {

    // MARK: - parse 新命令

    @Test("parse /new → .newSession")
    func parseNew() {
        #expect(SlashCommand.parse("/new") == .newSession)
    }

    @Test("parse /fork → .fork")
    func parseFork() {
        #expect(SlashCommand.parse("/fork") == .fork)
    }

    @Test("parse /archive → .archive")
    func parseArchive() {
        #expect(SlashCommand.parse("/archive") == .archive)
    }

    // MARK: - 大小写不敏感

    @Test("parse /NEW → .newSession (大小写不敏感)")
    func parseNewCaseInsensitive() {
        #expect(SlashCommand.parse("/NEW") == .newSession)
    }

    @Test("parse /Fork → .fork (大小写不敏感)")
    func parseForkCaseInsensitive() {
        #expect(SlashCommand.parse("/Fork") == .fork)
    }

    // MARK: - helpText

    @Test("/new helpText 包含 '新会话'")
    func newHelpText() {
        #expect(SlashCommand.newSession.helpText.contains("新会话"))
    }

    @Test("/fork helpText 包含 '分叉'")
    func forkHelpText() {
        #expect(SlashCommand.fork.helpText.contains("分叉"))
    }

    @Test("/archive helpText 包含 '归档'")
    func archiveHelpText() {
        #expect(SlashCommand.archive.helpText.contains("归档"))
    }

    // MARK: - acceptsArgs

    @Test("/new acceptsArgs == false")
    func newAcceptsNoArgs() {
        #expect(SlashCommand.newSession.acceptsArgs == false)
    }

    @Test("/fork acceptsArgs == false")
    func forkAcceptsNoArgs() {
        #expect(SlashCommand.fork.acceptsArgs == false)
    }

    @Test("/archive acceptsArgs == false")
    func archiveAcceptsNoArgs() {
        #expect(SlashCommand.archive.acceptsArgs == false)
    }

    // MARK: - availableDuringTask

    @Test("/new availableDuringTask == false")
    func newNotDuringTask() {
        #expect(SlashCommand.newSession.availableDuringTask == false)
    }

    @Test("/fork availableDuringTask == false")
    func forkNotDuringTask() {
        #expect(SlashCommand.fork.availableDuringTask == false)
    }

    @Test("/archive availableDuringTask == false")
    func archiveNotDuringTask() {
        #expect(SlashCommand.archive.availableDuringTask == false)
    }

    // MARK: - allCases count 更新

    @Test("allCases count == 13 (原 10 + newSession/fork/archive)")
    func allCasesCount() {
        #expect(SlashCommand.allCases.count == 13)
    }

    // MARK: - /help 输出包含新命令

    @Test("handleHelp 输出包含 /new /fork /archive")
    func handleHelpContainsNewCommands() {
        let output = SlashCommandHandler.handleHelp()
        #expect(output.contains("/new"))
        #expect(output.contains("/fork"))
        #expect(output.contains("/archive"))
    }
}
