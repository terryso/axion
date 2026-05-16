import Testing
import Foundation
import ArgumentParser
@testable import AxionCLI

@Suite("HelpOutput")
struct HelpOutputTests {

    @Test("discussion contains Claude Code config example")
    func discussionContainsClaudeCodeConfig() throws {
        let discussion = McpCommand.configuration.discussion
        #expect(discussion.contains("mcpServers"))
        #expect(discussion.contains("\"axion\""))
    }

    @Test("discussion contains verbose option")
    func discussionContainsVerboseOption() throws {
        let discussion = McpCommand.configuration.discussion
        #expect(discussion.contains("--verbose"))
        #expect(discussion.contains("stderr"))
    }

    @Test("discussion contains tool list")
    func discussionContainsToolList() throws {
        let discussion = McpCommand.configuration.discussion
        #expect(discussion.contains("run_task"))
        #expect(discussion.contains("query_task_status"))
    }

    @Test("discussion contains settings.json example")
    func discussionContainsSettingJsonExample() throws {
        let discussion = McpCommand.configuration.discussion
        #expect(discussion.contains("settings.json"))
        #expect(discussion.contains("\"command\": \"axion\""))
        #expect(discussion.contains("\"args\": [\"mcp\"]"))
    }

    @Test("actual --help output contains config example")
    func actualOutputContainsConfigExample() async throws {
        let axionBinary = findAxionBinary()
        guard FileManager.default.fileExists(atPath: axionBinary.path) else {
            return
        }

        let process = Process()
        let stdoutPipe = Pipe()
        process.executableURL = axionBinary
        process.arguments = ["mcp", "--help"]
        process.standardOutput = stdoutPipe

        try process.run()
        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        #expect(output.contains("mcpServers"))
        #expect(output.contains("settings.json"))
        #expect(output.contains("--verbose"))
    }

    private func findAxionBinary() -> URL {
        let projectRoot = Self.findProjectRoot()

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

    private static func findProjectRoot() -> URL {
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
}
