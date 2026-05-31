import Foundation
import OpenAgentSDK

struct TGCommandRouter: Sendable {
    private let registry: TGCommandRegistry

    init(registry: TGCommandRegistry) {
        self.registry = registry
    }

    /// Returns reply text for a command message, or nil if not a command.
    func handle(_ text: String, chatId: Int64) async -> String? {
        guard text.hasPrefix("/") else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstToken = trimmed.split(separator: " ").first.map(String.init) ?? trimmed

        guard let def = registry.resolve(firstToken) else {
            return unknownCommandReply()
        }
        return await def.handler(chatId)
    }

    private func unknownCommandReply() -> String {
        let names = registry.allCommands().map { "/\($0.name)" }
        return "未知命令。可用命令：\(names.joined(separator: ", "))"
    }
}
