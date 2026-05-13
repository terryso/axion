import XCTest
import ArgumentParser
@testable import AxionCLI

// [P1] ATDD — Story 6.2 AC3: --help 输出验证

final class HelpOutputTests: XCTestCase {

    // MARK: - AC3: --help 用法说明

    func test_mcpHelp_discussionContainsClaudeCodeConfig() throws {
        let discussion = McpCommand.configuration.discussion ?? ""
        XCTAssertTrue(discussion.contains("mcpServers"),
                      "Discussion should contain mcpServers configuration example")
        XCTAssertTrue(discussion.contains("\"axion\""),
                      "Discussion should contain axion server name in config example")
    }

    func test_mcpHelp_discussionContainsVerboseOption() throws {
        let discussion = McpCommand.configuration.discussion ?? ""
        XCTAssertTrue(discussion.contains("--verbose"),
                      "Discussion should mention --verbose option")
        XCTAssertTrue(discussion.contains("stderr"),
                      "Discussion should explain verbose logs go to stderr")
    }

    func test_mcpHelp_discussionContainsToolList() throws {
        let discussion = McpCommand.configuration.discussion ?? ""
        XCTAssertTrue(discussion.contains("run_task"),
                      "Discussion should list run_task tool")
        XCTAssertTrue(discussion.contains("query_task_status"),
                      "Discussion should list query_task_status tool")
    }

    func test_mcpHelp_discussionContainsSettingJsonExample() throws {
        let discussion = McpCommand.configuration.discussion ?? ""
        XCTAssertTrue(discussion.contains("settings.json"),
                      "Discussion should mention settings.json")
        XCTAssertTrue(discussion.contains("\"command\": \"axion\""),
                      "Discussion should contain command example")
        XCTAssertTrue(discussion.contains("\"args\": [\"mcp\"]"),
                      "Discussion should contain args example")
    }

    func test_mcpHelp_actualOutputContainsConfigExample() async throws {
        // Verify the actual --help output includes the Claude Code config example
        let axionBinary = findAxionBinary()
        guard FileManager.default.fileExists(atPath: axionBinary.path) else {
            throw XCTSkip("AxionCLI binary not found at \(axionBinary.path)")
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

        XCTAssertTrue(output.contains("mcpServers"),
                       "--help output should contain mcpServers config. Got: \(output)")
        XCTAssertTrue(output.contains("settings.json"),
                       "--help output should mention settings.json. Got: \(output)")
        XCTAssertTrue(output.contains("--verbose"),
                       "--help output should mention --verbose. Got: \(output)")
    }

    // MARK: - Helpers

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
