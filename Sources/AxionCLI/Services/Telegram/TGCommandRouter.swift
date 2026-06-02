import Foundation
import OpenAgentSDK

struct TGCommandRouter: Sendable {
    private let registry: TGCommandRegistry
    private let skillNameChecker: @Sendable (String) -> Bool

    init(registry: TGCommandRegistry, skillNameChecker: @Sendable @escaping (String) -> Bool = { _ in false }) {
        self.registry = registry
        self.skillNameChecker = skillNameChecker
    }

    /// Returns reply result for a command message, or nil if not a command.
    /// Returns nil for skill-like commands (e.g. "/webwright ...") so they
    /// fall through to the task queue as normal task text.
    func handle(_ text: String, chatId: Int64) async -> TGCommandResult? {
        guard text.hasPrefix("/") else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstToken = trimmed.split(separator: " ").first.map(String.init) ?? trimmed

        if let def = registry.resolve(firstToken) {
            return await def.handler(chatId)
        }

        // Not a built-in command — check if it matches a skill name.
        // If so, return nil so the full text reaches the task queue.
        let skillName = TGCommandRegistry.normalize(firstToken)
        if skillNameChecker(skillName) {
            return nil
        }

        return unknownCommandReply()
    }

    private func unknownCommandReply() -> TGCommandResult {
        let names = registry.allCommands().map { "/\($0.name)" }
        return TGCommandResult(text: "未知命令。可用命令：\(names.joined(separator: ", "))", markup: nil)
    }
}
