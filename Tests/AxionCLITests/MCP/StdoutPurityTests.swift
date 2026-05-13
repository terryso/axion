import XCTest
@testable import AxionCLI

// [P1] ATDD — Story 6.2 AC4: stdout 纯净验证

final class StdoutPurityTests: XCTestCase {

    // MARK: - AC4: stdout 无非 MCP 内容

    func test_mcpServerRunner_noPrintCalls() async throws {
        // Verify the REAL MCPServerRunner source code contains no print() calls
        let sourcePath = Self.projectRoot()
            .appendingPathComponent("Sources/AxionCLI/MCP/MCPServerRunner.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        // Check no print( calls exist (excluding // comments)
        let lines = source.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            XCTAssertFalse(
                trimmed.contains("print("),
                "MCPServerRunner.swift:\(index + 1) should not use print() — use fputs(..., stderr) instead"
            )
        }
    }

    func test_mcpCommand_run_noDirectStdout() async throws {
        // Verify the REAL McpCommand source code contains no print() calls
        let sourcePath = Self.projectRoot()
            .appendingPathComponent("Sources/AxionCLI/Commands/McpCommand.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        let lines = source.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            XCTAssertFalse(
                trimmed.contains("print("),
                "McpCommand.swift:\(index + 1) should not use print() — use fputs(..., stderr) instead"
            )
        }
    }

    func test_mcpServerRunner_allOutputUsesStderr() async throws {
        // Verify every fputs call in MCPServerRunner passes stderr as the stream
        let sourcePath = Self.projectRoot()
            .appendingPathComponent("Sources/AxionCLI/MCP/MCPServerRunner.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        let lines = source.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            guard trimmed.contains("fputs(") else { continue }

            XCTAssertFalse(
                trimmed.contains("stdout"),
                "MCPServerRunner.swift:\(index + 1) fputs should use stderr, not stdout"
            )
        }
    }

    func test_axionMcpProcess_stderrHasOutputOnMissingConfig() async throws {
        // Launch real `axion mcp` process — without config it exits with error to stderr
        // Key assertion: stdout should be empty (no leaked output)
        let axionBinary = productsBinaryURL()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = axionBinary
        process.arguments = ["mcp"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Give it a moment to produce output and exit
        try await Task.sleep(for: .milliseconds(2000))

        let stderrContent = readAvailableData(stderrPipe)
        let stdoutContent = readAvailableData(stdoutPipe)

        process.terminate()

        // stderr should have some output (error message about missing config)
        XCTAssertFalse(stderrContent.isEmpty,
                        "stderr should contain error output when config is missing")

        // stdout must be completely empty — no leaked prints, no partial MCP output
        XCTAssertTrue(stdoutContent.isEmpty,
                       "stdout must be empty — all output goes to stderr. Got: '\(stdoutContent)'")
    }

    func test_axionMcpProcess_stderrContainsErrorOnMissingHelper() async throws {
        // Even with API key, missing Helper should output error to stderr only
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

        // stderr should have error (Helper not found or config missing)
        XCTAssertFalse(stderrContent.isEmpty, "stderr should contain error output")

        // stdout must be empty regardless of which error path is hit
        XCTAssertTrue(stdoutContent.isEmpty,
                       "stdout must remain empty even on error. Got: '\(stdoutContent)'")
    }

    // MARK: - Helpers

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

        // Return best guess even if not found (test will fail with clear error)
        return candidates[0]
    }

    private func readAvailableData(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: .utf8) ?? ""
    }
}
