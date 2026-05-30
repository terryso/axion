import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI

@Suite("TGCommandRouter")
struct TGCommandRouterTests {

    // MARK: - /status Command (AC #1)

    @Test("/status returns gateway status")
    func statusCommandReturnsStatus() async throws {
        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 2,
                    uptimeSeconds: 3665,
                    label: "dev.axion.gateway",
                    tgConnected: "connected"
                )
            },
            skillsProvider: { [] }
        )

        let reply = await router.handle("/status", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("状态: running"))
        #expect(text.contains("运行中任务: 2"))
        #expect(text.contains("运行时长: 1h 1m 5s"))
        #expect(text.contains("TG 连接: connected"))
    }

    @Test("/status with zero uptime shows minutes and seconds")
    func statusCommandShortUptime() async throws {
        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 45,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { [] }
        )

        let reply = await router.handle("/status", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("0m 45s"))
        #expect(text.contains("运行中任务: 0"))
    }

    @Test("/status includes skill count")
    func statusCommandIncludesSkillCount() async throws {
        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: {
                [
                    Skill(name: "a", promptTemplate: "t"),
                    Skill(name: "b", promptTemplate: "t"),
                    Skill(name: "c", promptTemplate: "t"),
                ]
            }
        )

        let reply = await router.handle("/status", chatId: 100)
        let text = try #require(reply)
        #expect(text.contains("可用技能: 3 个"))
    }

    // MARK: - /skills Command (AC #2)

    @Test("/skills returns skill list")
    func skillsCommandReturnsList() async throws {
        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: {
                [
                    Skill(name: "commit", description: "Create a git commit", promptTemplate: "t"),
                    Skill(name: "review", description: "Review code changes", promptTemplate: "t"),
                ]
            }
        )

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
        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { [] }
        )

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        #expect(text == "暂无可用技能")
    }

    @Test("/skills list is sorted alphabetically")
    func skillsCommandSorted() async throws {
        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: {
                [
                    Skill(name: "zebra", description: "Z skill", promptTemplate: "t"),
                    Skill(name: "alpha", description: "A skill", promptTemplate: "t"),
                    Skill(name: "middle", description: "M skill", promptTemplate: "t"),
                ]
            }
        )

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        let lines = text.components(separatedBy: "\n")
        // lines[0] = header, lines[1] = alpha, lines[2] = middle, lines[3] = zebra
        #expect(lines[1].contains("alpha"))
        #expect(lines[2].contains("middle"))
        #expect(lines[3].contains("zebra"))
    }

    // MARK: - Unknown Command (AC #3)

    @Test("Unknown command returns help message")
    func unknownCommandReturnsHelp() async throws {
        let router = makeRouter()

        let reply = await router.handle("/unknown_command", chatId: 100)
        let text = try #require(reply)
        #expect(text == "未知命令。可用命令：/status, /skills, /new")
    }

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

    // MARK: - Non-Command Text (AC #3 implicit)

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

    // MARK: - /skills long list splitting (AC #2)

    @Test("/skills long list produces text suitable for splitMessage")
    func skillsLongListFormat() async throws {
        let skills: [Skill] = (0..<100).map { i in
            Skill(
                name: "skill_\(String(format: "%03d", i))",
                description: String(repeating: "x", count: 40),
                promptTemplate: "t"
            )
        }

        let router = TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 0,
                    label: "dev.axion.gateway"
                )
            },
            skillsProvider: { skills }
        )

        let reply = await router.handle("/skills", chatId: 100)
        let text = try #require(reply)
        // Text should be long but properly formatted; TelegramAdapter's splitMessage handles 4096 limit
        #expect(text.count > 4096)
        // Verify format is correct: each skill on its own line
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 101) // header + 100 skills
    }

    // MARK: - /new Command

    @Test("/new clears session and returns confirmation")
    func newCommandClearsSession() async throws {
        final class Collector: @unchecked Sendable {
            var ids: [Int64] = []
            func add(_ id: Int64) { ids.append(id) }
        }
        let collector = Collector()
        let router = makeRouter(clearSession: { chatId in
            collector.add(chatId)
        })

        let reply = await router.handle("/new", chatId: 42)
        let text = try #require(reply)
        #expect(text == "新会话已开始")
        #expect(collector.ids == [42])
    }

    @Test("/new without clearSession callback still returns confirmation")
    func newCommandWithoutCallback() async throws {
        let router = makeRouter()

        let reply = await router.handle("/new", chatId: 100)
        let text = try #require(reply)
        #expect(text == "新会话已开始")
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

    // MARK: - Helpers

    private func makeRouter(clearSession: (@Sendable (Int64) -> Void)? = nil) -> TGCommandRouter {
        TGCommandRouter(
            statusProvider: {
                GatewayRunnerStatus(
                    state: "running",
                    activeTaskCount: 0,
                    uptimeSeconds: 60,
                    label: "dev.axion.gateway",
                    tgConnected: "connected"
                )
            },
            skillsProvider: { [] },
            clearSession: clearSession
        )
    }
}
