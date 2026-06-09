import Foundation
import Testing

@testable import AxionCLI

@Suite("SlashCommandContext (AC3)")
struct SlashCommandContextTests {

    // MARK: - Default context (no filtering)

    @Test("默认上下文不过滤任何命令")
    func defaultContextNoFilter() {
        let ctx = SlashCommandContext(isAgentBusy: false, isSideSession: false)
        let result = ctx.filter(SlashCommand.allCases)
        #expect(result.count == SlashCommand.allCases.count)
    }

    // MARK: - Agent busy filtering

    @Test("agent 忙碌时排除 /resume")
    func agentBusyFiltersResume() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let result = ctx.filter(SlashCommand.allCases)
        #expect(!result.contains(.resume))
        #expect(result.contains(.help))
        #expect(result.contains(.cost))
        #expect(result.contains(.exit))
    }

    @Test("agent 忙碌时保留 help/cost/config/clear/exit/compact/model")
    func agentBusyKeepsCoreCommands() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let result = ctx.filter(SlashCommand.allCases)
        let expectedKept: [SlashCommand] = [.help, .clear, .compact, .model, .cost, .config, .exit]
        for cmd in expectedKept {
            #expect(result.contains(cmd), "\(cmd.rawValue) should be available when agent is busy")
        }
    }

    @Test("agent 忙碌时过滤后只有 10 个命令")
    func agentBusyResultCount() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let result = ctx.filter(SlashCommand.allCases)
        #expect(result.count == 10)
    }

    // MARK: - Side session filtering (all available now)

    @Test("side 会话不过滤任何命令（功能延后）")
    func sideSessionNoFilter() {
        let ctx = SlashCommandContext(isAgentBusy: false, isSideSession: true)
        let result = ctx.filter(SlashCommand.allCases)
        #expect(result.count == SlashCommand.allCases.count)
    }

    @Test("agent 忙碌 + side 会话双重过滤")
    func agentBusyAndSideSession() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: true)
        let result = ctx.filter(SlashCommand.allCases)
        #expect(!result.contains(.resume))
        // 所有命令 availableInSide == true，所以 side session 不额外过滤
        #expect(result.count == 10)
    }

    // MARK: - Empty input

    @Test("空数组输入返回空数组")
    func emptyInput() {
        let ctx = SlashCommandContext(isAgentBusy: true, isSideSession: false)
        let result = ctx.filter([])
        #expect(result.isEmpty)
    }
}
