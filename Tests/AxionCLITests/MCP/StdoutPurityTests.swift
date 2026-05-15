import Testing
import Foundation
@testable import AxionCLI

@Suite("StdoutPurity")
struct StdoutPurityTests {

    @Test("MCPServerRunner has no print() calls")
    func mcpServerRunnerNoPrintCalls() async throws {
        let sourcePath = Self.projectRoot()
            .appendingPathComponent("Sources/AxionCLI/MCP/MCPServerRunner.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        let lines = source.components(separatedBy: .newlines)
        for (_, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            #expect(!trimmed.contains("print("))
        }
    }

    @Test("McpCommand has no print() calls")
    func mcpCommandRunNoDirectStdout() async throws {
        let sourcePath = Self.projectRoot()
            .appendingPathComponent("Sources/AxionCLI/Commands/McpCommand.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        let lines = source.components(separatedBy: .newlines)
        for (_, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            #expect(!trimmed.contains("print("))
        }
    }

    @Test("MCPServerRunner all output uses stderr")
    func mcpServerRunnerAllOutputUsesStderr() async throws {
        let sourcePath = Self.projectRoot()
            .appendingPathComponent("Sources/AxionCLI/MCP/MCPServerRunner.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        let lines = source.components(separatedBy: .newlines)
        for (_, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            guard trimmed.contains("fputs(") else { continue }

            #expect(!trimmed.contains("stdout"))
        }
    }

    @Test("axion mcp process stderr has output on missing config")
    func axionMcpProcessStderrHasOutputOnMissingConfig() async throws {
        let axionBinary = productsBinaryURL()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = axionBinary
        process.arguments = ["mcp"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        try await Task.sleep(for: .milliseconds(2000))

        let stderrContent = readAvailableData(stderrPipe)
        let stdoutContent = readAvailableData(stdoutPipe)

        process.terminate()

        #expect(!stderrContent.isEmpty)

        #expect(stdoutContent.isEmpty)
    }

    @Test("axion mcp process stderr contains error on missing helper")
    func axionMcpProcessStderrContainsErrorOnMissingHelper() async throws {
        let axionBinary = productsBinaryURL()

        let process = Process()
        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.executableURL = axionBinary
        process.arguments = ["mcp"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = [
            "AXION_API_KEY": "test-key-for-stdout-purity",
            "HOME": "/tmp/axion-test-nohome-\(UUID().uuidString.prefix(8))",
        ]

        try process.run()

        try await Task.sleep(for: .milliseconds(2000))

        let stderrContent = readAvailableData(stderrPipe)
        let stdoutContent = readAvailableData(stdoutPipe)

        process.terminate()

        #expect(!stderrContent.isEmpty)

        #expect(stdoutContent.isEmpty)
    }

    private static func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #file)
        while url.path != "/" {
            let packageSwift = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        fatalError("Could not find project root (Package.swift not found)")
    }

    private func productsBinaryURL() -> URL {
        let projectRoot = Self.projectRoot()

        let candidates = [
            projectRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/AxionCLI"),
            projectRoot.appendingPathComponent(".build/debug/AxionCLI"),
            projectRoot.appendingPathComponent(".build/release/AxionCLI"),
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return candidates[0]
    }

    private func readAvailableData(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: .utf8) ?? ""
    }
}
