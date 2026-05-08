import Foundation
import XCTest

// ATDD Red-Phase Test Scaffolds for Story 1.6
// AC: #4 - 单操作性能 (NFR3: < 200ms)
// These tests measure individual MCP tool call response times through a real Helper process.
// They require macOS with AX permissions and a built AxionHelper binary.
// Priority: P1 (NFR3 verification — performance quality gate)

final class SingleOperationPerformanceTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        signal(SIGPIPE, SIG_IGN)
    }

    // MARK: - Helpers

    private var helperExecutablePath: String {
        let projectRoot = FileManager.default.currentDirectoryPath
        let debugPath = "\(projectRoot)/.build/debug/AxionHelper"
        let releasePath = "\(projectRoot)/.build/release/AxionHelper"
        if FileManager.default.fileExists(atPath: debugPath) { return debugPath }
        if FileManager.default.fileExists(atPath: releasePath) { return releasePath }
        return debugPath
    }

    private let initializeRequest = """
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

    """

    private let listAppsRequest = """
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}

    """

    /// Starts Helper, sends initialize, waits for response, returns process and pipes.
    private func startHelperAndInitialize() async throws -> (Process, Pipe, Pipe) {
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            throw XCTSkip("AxionHelper not built. Run `swift build` first.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperExecutablePath)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms settle

        // Send initialize
        guard let initData = initializeRequest.data(using: .utf8) else {
            XCTFail("Failed to encode initialize request")
            return (process, stdinPipe, stdoutPipe)
        }
        stdinPipe.fileHandleForWriting.write(initData)

        // Wait for initialize response
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        guard responseData.count > 0 else {
            XCTFail("No initialize response received")
            return (process, stdinPipe, stdoutPipe)
        }

        return (process, stdinPipe, stdoutPipe)
    }

    /// Reads a JSON-RPC response from stdout after sending a request.
    private func readResponse(from stdoutPipe: Pipe, timeout: TimeInterval = 3.0) async throws -> Data {
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        return responseData
    }

    // MARK: - AC4: NFR3 — Single operation < 200ms

    // [P1] list_apps response time through real Helper process is under 200ms (NFR3)
    func test_listApps_responseTime_under200ms() async throws {
        // Given: Helper is running and MCP is initialized
        let (process, stdinPipe, stdoutPipe) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        // When: Sending list_apps tool call and measuring round-trip time
        guard let requestData = listAppsRequest.data(using: .utf8) else {
            XCTFail("Failed to encode list_apps request")
            return
        }

        let startTime = Date()
        stdinPipe.fileHandleForWriting.write(requestData)
        let responseData = try await readResponse(from: stdoutPipe, timeout: 3.0)
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Response received and round-trip < 200ms (NFR3)
        XCTAssertGreaterThan(responseData.count, 0, "Should receive list_apps response")

        // Parse response to verify it's valid JSON
        let responseString = String(data: responseData, encoding: .utf8) ?? ""
        // Response may contain multiple JSON objects (initialize + list_apps); find the list_apps one
        XCTAssertTrue(
            responseString.contains("list_apps") || responseString.contains("result"),
            "Response should contain tool result. Got: \(responseString.prefix(200))"
        )

        XCTAssertLessThan(
            elapsed, 0.2,
            "list_apps round-trip should be < 200ms (NFR3), took \(String(format: "%.3f", elapsed))s"
        )
    }

    // [P1] get_window_state response time through real Helper is under 200ms (NFR3)
    func test_getWindowState_responseTime_under200ms() async throws {
        // Given: Helper is running and MCP is initialized
        let (process, stdinPipe, stdoutPipe) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        let getWindowStateRequest = """
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_window_state","arguments":{"window_id":1}}}

        """

        // When: Sending get_window_state tool call and measuring round-trip
        guard let requestData = getWindowStateRequest.data(using: .utf8) else {
            XCTFail("Failed to encode get_window_state request")
            return
        }

        let startTime = Date()
        stdinPipe.fileHandleForWriting.write(requestData)
        let responseData = try await readResponse(from: stdoutPipe, timeout: 3.0)
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Response received — NFR3 allows 200ms for round-trip
        XCTAssertGreaterThan(responseData.count, 0, "Should receive get_window_state response")

        // Note: get_window_state may return error for window_id=1 (window not found),
        // but the response time should still be fast
        XCTAssertLessThan(
            elapsed, 0.2,
            "get_window_state round-trip should be < 200ms (NFR3), took \(String(format: "%.3f", elapsed))s"
        )
    }
}
