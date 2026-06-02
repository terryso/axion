import ArgumentParser
import Foundation

/// `axion memory clear --app <domain>` — delete a specific App's Memory file.
/// `axion memory clear --type <memory|user>` — clear a universal memory file.
///
/// Exactly one of `--app` or `--type` must be provided.
struct MemoryClearCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "清除指定 App 的 Memory"
    )

    @Option(name: .long, help: "要清除的 App domain（如 com.apple.calculator）")
    var app: String?

    @Option(name: .long, help: "Universal memory type to clear: memory or user")
    var type: String?

    func run() async throws {
        let memoryDir = resolveMemoryDir()

        try Self.validateOptions(app: app, type: type)

        if let type = type {
            let result = try await Self.clearType(type, memoryDir: memoryDir)
            print(result.message)
        } else if let app = app {
            let result = try await Self.clearDomain(app, memoryDir: memoryDir)
            print(result.message)
        }
    }

    // MARK: - Public Static API (for testing)

    /// Result of a clear operation.
    struct ClearResult {
        let success: Bool
        let message: String
    }

    /// Validate that exactly one of --app or --type is provided.
    static func validateOptions(app: String?, type: String?) throws {
        let hasApp = app != nil
        let hasType = type != nil
        guard hasApp != hasType else {
            throw ValidationError("Exactly one of --app or --type must be specified")
        }
    }

    /// Clear a universal memory file by type ("memory" or "user").
    static func clearType(_ type: String, memoryDir: String) async throws -> ClearResult {
        guard let target = parseTypeArgument(type) else {
            throw ValidationError("Invalid type: '\(type)'. Use 'memory' or 'user'")
        }
        let store = UniversalMemoryStore(memoryDir: memoryDir)
        await store.write(target: target, content: "")
        return ClearResult(success: true, message: "Cleared \(type) memory")
    }

    /// Clear the Memory file for a specific domain.
    ///
    /// - Parameters:
    ///   - domain: The App domain to clear (e.g., "com.apple.calculator").
    ///   - memoryDir: The filesystem path to the Memory directory.
    /// - Returns: A `ClearResult` indicating whether the deletion succeeded.
    static func clearDomain(_ domain: String, memoryDir: String) async throws -> ClearResult {
        guard isValidDomain(domain) else {
            return ClearResult(
                success: false,
                message: "Invalid domain: '\(domain)'. Domain must not contain path separators or '..'."
            )
        }
        let dir = memoryDir as NSString
        let legacyPath = dir.appendingPathComponent("\(domain).json")
        let factsPath = dir.appendingPathComponent("\(domain)-facts.json")
        let fm = FileManager.default

        let legacyExists = fm.fileExists(atPath: legacyPath)
        let factsExists = fm.fileExists(atPath: factsPath)

        guard legacyExists || factsExists else {
            return ClearResult(
                success: false,
                message: "No Memory found for '\(domain)'."
            )
        }

        do {
            if legacyExists { try fm.removeItem(atPath: legacyPath) }
            if factsExists { try fm.removeItem(atPath: factsPath) }
            return ClearResult(
                success: true,
                message: "Memory cleared for '\(domain)'."
            )
        } catch {
            return ClearResult(
                success: false,
                message: "Failed to clear Memory for '\(domain)': \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private Helpers

    private static func parseTypeArgument(_ raw: String) -> MemoryTarget? {
        switch raw {
        case "memory": return .memory
        case "user": return .user
        default: return nil
        }
    }

    /// Resolve the default Memory directory path.
    private func resolveMemoryDir() -> String {
        let configDir = ConfigManager.defaultConfigDirectory
        return (configDir as NSString).appendingPathComponent("memory")
    }

    /// Validate that a domain string is safe to use as a filename component.
    /// Rejects domains containing path separators or parent-directory references.
    private static func isValidDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty else { return false }
        let forbidden = ["/", "\\", ".."]
        for segment in forbidden {
            if domain.contains(segment) { return false }
        }
        return true
    }
}
