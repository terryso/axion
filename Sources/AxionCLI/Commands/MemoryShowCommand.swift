import ArgumentParser

/// `axion memory show <memory|user>` — display universal memory content.
struct MemoryShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "显示通用记忆内容"
    )

    @Argument(help: "记忆类型：memory 或 user")
    var target: String

    func run() async throws {
        let output = try await Self.showContent(target: target, memoryDir: ConfigManager.memoryDirectory)
        print(output)
    }

    // MARK: - Public Static API (for testing)

    static func showContent(target: String, memoryDir: String) async throws -> String {
        guard let memTarget = parseTarget(target) else {
            throw ValidationError("Invalid target: '\(target)'. Use 'memory' or 'user'")
        }
        let store = UniversalMemoryStore(memoryDir: memoryDir)
        let content = await store.read(target: memTarget)
        if content.isEmpty {
            return "No content in \(target)."
        }
        return content
    }

    // MARK: - Private Helpers

    private static func parseTarget(_ raw: String) -> MemoryTarget? {
        switch raw {
        case "memory": return .memory
        case "user": return .user
        default: return nil
        }
    }

}
