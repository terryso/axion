import Foundation
import Testing
@testable import AxionCLI

@Suite("End-to-End Smoke")
struct EndToEndSmokeTests {

    // MARK: - 真实进程级 MCP 冒烟测试

    @Test("real process initialize and tools list")
    func realProcessInitializeAndToolsList() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["AXION_API_KEY"],
              !apiKey.isEmpty else {
            return
        }

        let axionBinary = findAxionBinary()
        guard FileManager.default.fileExists(atPath: axionBinary.path) else { return }

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

        try await Task.sleep(for: .milliseconds(1000))

        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0.0"}}}
        """
        try sendLine(stdinPipe, text: initRequest)

        try await Task.sleep(for: .milliseconds(1000))

        let stdoutData = readAvailable(stdoutPipe)
        let response = String(data: stdoutData, encoding: .utf8) ?? ""

        #expect(response.contains("initialize"),
                "Response should contain initialize result. Got: \(response)")

        let toolsRequest = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        """
        try sendLine(stdinPipe, text: toolsRequest)

        try await Task.sleep(for: .milliseconds(1000))

        let toolsData = readAvailable(stdoutPipe)
        let toolsResponse = String(data: toolsData, encoding: .utf8) ?? ""

        #expect(toolsResponse.contains("run_task"),
                "tools/list should expose run_task. Got: \(toolsResponse)")

        try stdinPipe.fileHandleForWriting.close()

        try await Task.sleep(for: .milliseconds(500))

        let stderrData = readAvailable(stderrPipe)
        let stderrContent = String(data: stderrData, encoding: .utf8) ?? ""

        #expect(stderrContent.contains("Axion MCP server"),
                "stderr should contain server log. Got: \(stderrContent)")

        process.terminate()
    }

    // MARK: - Helpers

    private func findAxionBinary() -> URL {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

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
