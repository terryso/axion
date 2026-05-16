import ArgumentParser
import Foundation

/// `axion memory clear --app <domain>` — delete a specific App's Memory file.
///
/// Removes the JSON file for the specified domain from the Memory directory.
/// If the domain does not exist, outputs a message (does not error).
/// Other domains are not affected.
struct MemoryClearCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "清除指定 App 的 Memory"
    )

    @Option(name: .long, help: "要清除的 App domain（如 com.apple.calculator）")
    var app: String

    func run() async throws {
        let memoryDir = resolveMemoryDir()
        let result = try await Self.clearDomain(app, memoryDir: memoryDir)
        print(result.message)
    }

    // MARK: - Public Static API (for testing)

    /// Result of a clear operation.
    struct ClearResult {
        let success: Bool
        let message: String
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
        let filePath = (memoryDir as NSString).appendingPathComponent("\(domain).json")
        let fm = FileManager.default

        guard fm.fileExists(atPath: filePath) else {
            return ClearResult(
                success: false,
                message: "No Memory found for '\(domain)'."
            )
        }

        do {
            try fm.removeItem(atPath: filePath)
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
