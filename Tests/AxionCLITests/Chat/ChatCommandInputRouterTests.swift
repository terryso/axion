import Testing

@testable import AxionCLI

@Suite("ChatCommandInputRouter")
struct ChatCommandInputRouterTests {

    // MARK: - Ignored Input

    @Test("empty input is ignored")
    func emptyInputIgnored() {
        #expect(ChatCommandInputRouter.route(input: "   ", resumeSessionIds: []) == .ignore)
    }

    @Test("Ctrl-C sentinel input is ignored")
    func ctrlCSentinelIgnored() {
        #expect(ChatCommandInputRouter.route(input: "^C", resumeSessionIds: []) == .ignore)
    }

    // MARK: - Built-in Slash Commands

    @Test("built-in slash command routes before agent execution")
    func builtInSlashCommandRoutes() {
        let route = ChatCommandInputRouter.route(input: "/help", resumeSessionIds: [])
        #expect(route == .builtIn(command: .help, argument: nil))
    }

    @Test("built-in slash command preserves argument")
    func builtInSlashCommandArgument() {
        let route = ChatCommandInputRouter.route(input: "/model sonnet", resumeSessionIds: [])
        #expect(route == .builtIn(command: .model, argument: "sonnet"))
    }

    @Test("generated task slash commands remain built-in routes")
    func generatedTaskSlashCommandsRouteBuiltIn() {
        #expect(
            ChatCommandInputRouter.route(input: "/apps chrome --all", resumeSessionIds: [])
                == .builtIn(command: .apps, argument: "chrome --all")
        )
        #expect(
            ChatCommandInputRouter.route(input: "/storage large", resumeSessionIds: [])
                == .builtIn(command: .storage, argument: "large")
        )
    }

    @Test("built-in command wins over same-named skill")
    func builtInWinsOverSkill() {
        let route = ChatCommandInputRouter.route(
            input: "/help",
            resumeSessionIds: [],
            resolveSkillName: { _ in "help" }
        )
        #expect(route == .builtIn(command: .help, argument: nil))
    }

    // MARK: - Resume List Selection

    @Test("resume list uses one-based index")
    func resumeListIndex() {
        let route = ChatCommandInputRouter.route(
            input: "2",
            resumeSessionIds: ["chat-1", "chat-2", "chat-3"]
        )
        #expect(route == .resumeListedSession(sessionId: "chat-2"))
    }

    @Test("resume list ignores zero and out-of-range numbers")
    func resumeListRejectsInvalidIndexes() {
        #expect(
            ChatCommandInputRouter.route(input: "0", resumeSessionIds: ["chat-1"])
                == .agentTask(text: "0", matchedSkill: nil)
        )
        #expect(
            ChatCommandInputRouter.route(input: "2", resumeSessionIds: ["chat-1"])
                == .agentTask(text: "2", matchedSkill: nil)
        )
    }

    // MARK: - Agent Tasks

    @Test("plain text routes to agent task")
    func plainTextRoutesToAgent() {
        let route = ChatCommandInputRouter.route(input: "hello", resumeSessionIds: [])
        #expect(route == .agentTask(text: "hello", matchedSkill: nil))
    }

    @Test("unknown slash routes to agent task without skill match")
    func unknownSlashRoutesToAgent() {
        let route = ChatCommandInputRouter.route(input: "/unknown do it", resumeSessionIds: [])
        #expect(route == .agentTask(text: "/unknown do it", matchedSkill: nil))
    }

    @Test("unknown slash with skill match carries canonical skill name and args")
    func unknownSlashSkillMatch() {
        let route = ChatCommandInputRouter.route(
            input: "/ci commit everything",
            resumeSessionIds: [],
            resolveSkillName: { rawName in rawName == "ci" ? "commit" : nil }
        )
        #expect(
            route == .agentTask(
                text: "/ci commit everything",
                matchedSkill: ChatSkillExecution(name: "commit", args: "commit everything")
            )
        )
    }

    @Test("unknown slash skill match omits empty args")
    func unknownSlashSkillMatchWithoutArgs() {
        let route = ChatCommandInputRouter.route(
            input: "/commit",
            resumeSessionIds: [],
            resolveSkillName: { rawName in rawName == "commit" ? "commit" : nil }
        )
        #expect(
            route == .agentTask(
                text: "/commit",
                matchedSkill: ChatSkillExecution(name: "commit", args: nil)
            )
        )
    }

    @Test("bare slash is treated as an agent task")
    func bareSlashRoutesToAgent() {
        let route = ChatCommandInputRouter.route(input: "/", resumeSessionIds: [])
        #expect(route == .agentTask(text: "/", matchedSkill: nil))
    }

    // MARK: - Slash Invocation Parser

    @Test("parseSlashInvocation splits command and argument once")
    func parseSlashInvocationSplitsOnce() throws {
        let invocation = try #require(ChatCommandInputRouter.parseSlashInvocation("/skill alpha beta"))
        #expect(invocation.name == "skill")
        #expect(invocation.args == "alpha beta")
    }

    @Test("parseSlashInvocation rejects non-slash input")
    func parseSlashInvocationRejectsNonSlash() {
        #expect(ChatCommandInputRouter.parseSlashInvocation("skill alpha") == nil)
    }
}
