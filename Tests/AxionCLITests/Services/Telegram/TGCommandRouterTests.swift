import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI

@Suite("TGCommandRouter")
struct TGCommandRouterTests {

    // MARK: - /status Command

    @Test("/status returns gateway status")
    func statusCommandReturnsStatus() async throws {
        let router = makeRouter()
        let reply = await router.handle("/status", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("状态: running"))
        #expect(text.contains("运行中任务: 2"))
        #expect(text.contains("运行时长: 1h 1m 5s"))
        #expect(text.contains("TG 连接: connected"))
    }

    @Test("/status with zero uptime shows minutes and seconds")
    func statusCommandShortUptime() async throws {
        var status = defaultStatus()
        status = GatewayRunnerStatus(state: "running", activeTaskCount: 0, uptimeSeconds: 45, label: "dev.axion.gateway")
        let registry = makeRegistry(status: status)
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/status", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("0m 45s"))
        #expect(text.contains("运行中任务: 0"))
    }

    @Test("/status includes skill count")
    func statusCommandIncludesSkillCount() async throws {
        let skills: [Skill] = [
            Skill(name: "a", promptTemplate: "t"),
            Skill(name: "b", promptTemplate: "t"),
            Skill(name: "c", promptTemplate: "t"),
        ]
        let registry = makeRegistry(skills: skills)
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/status", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("可用技能: 3 个"))
    }

    // MARK: - /skills Command

    @Test("/skills returns skill list")
    func skillsCommandReturnsList() async throws {
        let skills: [Skill] = [
            Skill(name: "commit", description: "Create a git commit", promptTemplate: "t"),
            Skill(name: "review", description: "Review code changes", promptTemplate: "t"),
        ]
        let registry = makeRegistry(skills: skills)
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("commit"))
        #expect(text.contains("Create a git commit"))
        #expect(text.contains("review"))
        #expect(text.contains("Review code changes"))
        #expect(text.contains("2 个"))
    }

    @Test("/skills with empty list returns no skills message")
    func skillsCommandEmptyList() async throws {
        let router = makeRouter()

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        #expect(text == "暂无可用技能")
    }

    @Test("/skills list is sorted alphabetically")
    func skillsCommandSorted() async throws {
        let skills: [Skill] = [
            Skill(name: "zebra", description: "Z skill", promptTemplate: "t"),
            Skill(name: "alpha", description: "A skill", promptTemplate: "t"),
            Skill(name: "middle", description: "M skill", promptTemplate: "t"),
        ]
        let registry = makeRegistry(skills: skills)
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[1].contains("alpha"))
        #expect(lines[2].contains("middle"))
        #expect(lines[3].contains("zebra"))
    }

    // MARK: - Unknown Command

    @Test("Unknown command returns available commands list")
    func unknownCommandReturnsHelp() async throws {
        let router = makeRouter()

        let reply = await router.handle("/unknown_command", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("未知命令"))
        #expect(text.contains("/help"))
        #expect(text.contains("/status"))
        #expect(text.contains("/skills"))
        #expect(text.contains("/new"))
        #expect(text.contains("/queue"))
    }

    // MARK: - Case Insensitivity

    @Test("Case-insensitive commands")
    func caseInsensitiveCommands() async throws {
        let router = makeRouter()

        let replyUpper = await router.handle("/STATUS", chatId: 100)
        #expect(replyUpper != nil)
        #expect(replyUpper!.contains("Gateway Status"))

        let replyMixed = await router.handle("/Skills", chatId: 100)
        #expect(replyMixed != nil)
        #expect(replyMixed!.contains("可用技能"))
    }

    // MARK: - Non-Command Text

    @Test("Non-command text returns nil")
    func nonCommandReturnsNil() async {
        let router = makeRouter()
        let reply = await router.handle("hello world", chatId: 100)
        #expect(reply == nil)
    }

    @Test("Empty string returns nil")
    func emptyStringReturnsNil() async {
        let router = makeRouter()
        let reply = await router.handle("", chatId: 100)
        #expect(reply == nil)
    }

    @Test("Text starting with letter returns nil")
    func textWithLetterPrefixReturnsNil() async {
        let router = makeRouter()
        let reply = await router.handle("do something", chatId: 100)
        #expect(reply == nil)
    }

    @Test("Command with trailing whitespace is handled")
    func commandWithTrailingWhitespace() async throws {
        let router = makeRouter()

        let reply = await router.handle("/status  ", chatId: 100)
        #expect(reply != nil)
        #expect(reply!.contains("Gateway Status"))
    }

    @Test("Command with trailing arguments uses first token only")
    func commandWithTrailingArgs() async throws {
        let router = makeRouter()

        let reply = await router.handle("/status hello world", chatId: 100)
        #expect(reply != nil)
        #expect(reply!.contains("Gateway Status"))
    }

    // MARK: - @botname Stripping

    @Test("Command with @botname suffix strips bot name")
    func commandWithBotnameSuffix() async throws {
        let router = makeRouter()

        let reply = await router.handle("/status@my_axion_bot", chatId: 100)
        #expect(reply != nil)
        #expect(reply!.contains("Gateway Status"))

        let replySkills = await router.handle("/skills@my_axion_bot", chatId: 100)
        #expect(replySkills != nil)
        #expect(replySkills!.contains("可用技能"))
    }

    // MARK: - /help Command

    @Test("/help returns getting-started guide")
    func helpCommandReturnsGuide() async throws {
        let router = makeRouter()

        let reply = await router.handle("/help", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("Axion"))
        #expect(text.contains("直接发送"))
        #expect(text.contains("/commands"))
        #expect(text.contains("/status"))
    }

    // MARK: - /commands Command

    @Test("/commands returns full command list")
    func commandsCommandReturnsList() async throws {
        let router = makeRouter()

        let reply = await router.handle("/commands", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("help"))
        #expect(text.contains("commands"))
        #expect(text.contains("status"))
        #expect(text.contains("skills"))
        #expect(text.contains("new"))
        #expect(text.contains("queue"))
    }

    // MARK: - /new Command

    @Test("/new clears session and returns confirmation")
    func newCommandClearsSession() async throws {
        final class Collector: @unchecked Sendable {
            var ids: [Int64] = []
            func add(_ id: Int64) { ids.append(id) }
        }
        let collector = Collector()
        let registry = makeRegistry(clearSession: { chatId in collector.add(chatId) })
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/new", chatId: 42)
        let text = try #require(reply)
        #expect(text == "新会话已开始")
        #expect(collector.ids == [42])
    }

    @Test("/new is case-insensitive")
    func newCommandCaseInsensitive() async throws {
        let router = makeRouter()

        let reply = await router.handle("/NEW", chatId: 100)
        #expect(reply == "新会话已开始")
    }

    @Test("/new with @botname suffix works")
    func newCommandWithBotname() async throws {
        let router = makeRouter()

        let reply = await router.handle("/new@my_bot", chatId: 100)
        #expect(reply == "新会话已开始")
    }

    // MARK: - /queue Command

    @Test("/queue returns per-chat queue status")
    func queueCommandReturnsStatus() async throws {
        let registry = makeRegistry(queueStatus: { chatId in
            return "队列: 空闲\n执行中: 否\n会话: 无"
        })
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/queue", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("队列"))
        #expect(text.contains("执行中"))
    }

    // MARK: - /skills long list splitting

    @Test("/skills long list produces text suitable for splitMessage")
    func skillsLongListFormat() async throws {
        let skills: [Skill] = (0..<100).map { i in
            Skill(
                name: "skill_\(String(format: "%03d", i))",
                description: String(repeating: "x", count: 40),
                promptTemplate: "t"
            )
        }
        let registry = makeRegistry(skills: skills)
        let router = TGCommandRouter(registry: registry)

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        #expect(text.count > 4096)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 101) // header + 100 skills
    }

    // MARK: - Helpers

    private func defaultStatus() -> GatewayRunnerStatus {
        GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 2,
            uptimeSeconds: 3665,
            label: "dev.axion.gateway",
            tgConnected: "connected"
        )
    }

    private func makeRegistry(
        status: GatewayRunnerStatus? = nil,
        skills: [Skill] = [],
        clearSession: (@Sendable (Int64) async -> Void)? = nil,
        queueStatus: (@Sendable (Int64) async -> String)? = nil
    ) -> TGCommandRegistry {
        let s = status ?? GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 2,
            uptimeSeconds: 3665,
            label: "dev.axion.gateway",
            tgConnected: "connected"
        )
        let statusProvider: @Sendable () async -> GatewayRunnerStatus = { s }
        let skillsProvider: @Sendable () -> [Skill] = { skills }
        let clearSessionHandler: @Sendable (Int64) async -> Void = clearSession ?? { _ in }
        let queueStatusHandler: @Sendable (Int64) async -> String = queueStatus ?? { chatId in "队列: 空闲\n执行中: 否\n会话: 无" }

        let coreRegistry = makeCoreRegistry(statusProvider: statusProvider, skillsProvider: skillsProvider)

        return TGCommandRegistry(commands: [
            TGCommandDef(name: "help", description: "入门指南", helpText: "", menuPriority: 1) { _ in
                "Axion 是一个桌面自动化助手。\n\n直接发送文本即可执行任务。\n\n可用命令:\n/commands — 查看所有命令\n/status — 查看网关状态\n/skills — 查看技能列表\n/new — 开始新会话\n/queue — 查看任务队列"
            },
            TGCommandDef(name: "commands", description: "查看所有命令", helpText: "", menuPriority: 2) { _ in
                let cmds = coreRegistry.allCommands()
                var lines = ["📋 可用命令:"]
                for cmd in cmds {
                    lines.append("  /\(cmd.name) — \(cmd.description)")
                }
                return lines.joined(separator: "\n")
            },
            TGCommandDef(name: "status", description: "查看网关状态", helpText: "", menuPriority: 3) { _ in
                await formatStatus(statusProvider: statusProvider, skillsProvider: skillsProvider)
            },
            TGCommandDef(name: "skills", description: "查看技能列表", helpText: "", menuPriority: 4) { _ in
                formatSkills(skillsProvider: skillsProvider)
            },
            TGCommandDef(name: "new", description: "开始新会话", helpText: "", menuPriority: 5) { chatId in
                await clearSessionHandler(chatId)
                return "新会话已开始"
            },
            TGCommandDef(name: "queue", description: "查看任务队列", helpText: "", menuPriority: 6) { chatId in
                await queueStatusHandler(chatId)
            },
        ])
    }

    /// Minimal registry for the /commands handler to reference.
    /// Avoids infinite recursion by only containing core command metadata.
    /// (The /commands handler captures this to list available commands.)
    private func makeCoreRegistry(
        statusProvider: @Sendable () async -> GatewayRunnerStatus,
        skillsProvider: @Sendable () -> [Skill]
    ) -> TGCommandRegistry {
        TGCommandRegistry(commands: [
            TGCommandDef(name: "help", description: "入门指南", helpText: "", menuPriority: 1) { _ in "" },
            TGCommandDef(name: "commands", description: "查看所有命令", helpText: "", menuPriority: 2) { _ in "" },
            TGCommandDef(name: "status", description: "查看网关状态", helpText: "", menuPriority: 3) { _ in "" },
            TGCommandDef(name: "skills", description: "查看技能列表", helpText: "", menuPriority: 4) { _ in "" },
            TGCommandDef(name: "new", description: "开始新会话", helpText: "", menuPriority: 5) { _ in "" },
            TGCommandDef(name: "queue", description: "查看任务队列", helpText: "", menuPriority: 6) { _ in "" },
        ])
    }

    private func makeRouter() -> TGCommandRouter {
        TGCommandRouter(registry: makeRegistry())
    }

    private func formatStatus(statusProvider: @Sendable () async -> GatewayRunnerStatus, skillsProvider: @Sendable () -> [Skill]) async -> String {
        let status = await statusProvider()
        let uptime = Int(status.uptimeSeconds)
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        let seconds = uptime % 60

        var lines = ["📊 Gateway Status"]
        lines.append("状态: \(status.state)")
        lines.append("运行中任务: \(status.activeTaskCount)")
        if hours > 0 {
            lines.append("运行时长: \(hours)h \(minutes)m \(seconds)s")
        } else {
            lines.append("运行时长: \(minutes)m \(seconds)s")
        }
        lines.append("TG 连接: \(status.tgConnected ?? "disabled")")
        let skills = skillsProvider()
        lines.append("可用技能: \(skills.count) 个")
        return lines.joined(separator: "\n")
    }

    private func formatSkills(skillsProvider: @Sendable () -> [Skill]) -> String {
        let skills = skillsProvider()
        guard !skills.isEmpty else {
            return "暂无可用技能"
        }

        var lines = ["📋 可用技能 (\(skills.count) 个):"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("  • \(skill.name): \(skill.description)")
        }
        return lines.joined(separator: "\n")
    }
}
