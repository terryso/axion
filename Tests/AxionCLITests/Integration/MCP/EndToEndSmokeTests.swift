import XCTest
@testable import AxionCLI

// [P1] Integration — Story 6.2 AC2: 端到端冒烟测试
// 仅本地手动运行：swift test --filter "EndToEndSmokeTests"

final class EndToEndSmokeTests: XCTestCase {

    // MARK: - 真实进程级 MCP 冒烟测试

    func test_realProcess_initializeAndToolsList() async throws {
        // This test requires a valid API key and Helper installed.
        // Skip if environment not set up.
        guard let apiKey = ProcessInfo.processInfo.environment["AXION_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("AXION_API_KEY not set — skipping real process MCP test")
        }

        let axionBinary = findAxionBinary()
        guard FileManager.default.fileExists(atPath: axionBinary.path) else {
            throw XCTSkip("AxionCLI binary not found at \(axionBinary.path)")
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = axionBinary
        process.arguments = ["mcp"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment

        try process.run()

        // Give server time to start
        try await Task.sleep(for: .milliseconds(1000))

        // Send MCP initialize request
        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0.0"}}}
        """
        try sendLine(stdinPipe, text: initRequest)

        try await Task.sleep(for: .milliseconds(1000))

        // Read response from stdout
        let stdoutData = readAvailable(stdoutPipe)
        let response = String(data: stdoutData, encoding: .utf8) ?? ""

        XCTAssertTrue(response.contains("initialize"),
                       "Response should contain initialize result. Got: \(response)")

        // Send tools/list request
        let toolsRequest = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        """
        try sendLine(stdinPipe, text: toolsRequest)

        try await Task.sleep(for: .milliseconds(1000))

        let toolsData = readAvailable(stdoutPipe)
        let toolsResponse = String(data: toolsData, encoding: .utf8) ?? ""

        XCTAssertTrue(toolsResponse.contains("run_task"),
                       "tools/list should expose run_task. Got: \(toolsResponse)")

        // Close stdin to trigger graceful shutdown
        try stdinPipe.fileHandleForWriting.close()

        try await Task.sleep(for: .milliseconds(500))

        let stderrData = readAvailable(stderrPipe)
        let stderrContent = String(data: stderrData, encoding: .utf8) ?? ""

        // stderr should have startup log (not stdout)
        XCTAssertTrue(stderrContent.contains("Axion MCP server"),
                       "stderr should contain server log. Got: \(stderrContent)")

        process.terminate()
    }

    // MARK: - Helpers

    private func findAxionBinary() -> URL {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MCP/
            .deletingLastPathComponent()  // Integration/
            .deletingLastPathComponent()  // AxionCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // axion/

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

    private func sendLine(_ pipe: Pipe, text: String) throws {
        let data = (text + "\n").data(using: .utf8)!
        try pipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func readAvailable(_ pipe: Pipe) -> Data {
        pipe.fileHandleForReading.availableData
    }
}
