import Foundation

struct ChatSkillExecution: Equatable, Sendable {
    let name: String
    let args: String?
}

enum ChatCommandInputRoute: Equatable, Sendable {
    case ignore
    case builtIn(command: SlashCommand, argument: String?)
    case resumeListedSession(sessionId: String)
    case agentTask(text: String, matchedSkill: ChatSkillExecution?)
}

struct ChatCommandInputRouter {
    typealias SkillNameResolver = @Sendable (String) -> String?

    static func route(
        input: String,
        resumeSessionIds: [String],
        resolveSkillName: SkillNameResolver = { _ in nil }
    ) -> ChatCommandInputRoute {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "^C" else {
            return .ignore
        }

        if let command = SlashCommand.parse(trimmed) {
            return .builtIn(command: command, argument: SlashCommand.parseArgument(trimmed))
        }

        if !resumeSessionIds.isEmpty,
           let index = Int(trimmed),
           index > 0,
           index <= resumeSessionIds.count
        {
            return .resumeListedSession(sessionId: resumeSessionIds[index - 1])
        }

        if let invocation = parseSlashInvocation(trimmed),
           let resolvedName = resolveSkillName(invocation.name)
        {
            return .agentTask(
                text: trimmed,
                matchedSkill: ChatSkillExecution(name: resolvedName, args: invocation.args)
            )
        }

        return .agentTask(text: trimmed, matchedSkill: nil)
    }

    static func parseSlashInvocation(_ input: String) -> (name: String, args: String?)? {
        guard input.hasPrefix("/") else {
            return nil
        }

        let parts = input.split(separator: " ", maxSplits: 1)
        guard let commandPart = parts.first else {
            return nil
        }

        let name = String(commandPart.dropFirst())
        guard !name.isEmpty else {
            return nil
        }

        let args = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : ""

        return (name: name, args: args.isEmpty ? nil : args)
    }
}
