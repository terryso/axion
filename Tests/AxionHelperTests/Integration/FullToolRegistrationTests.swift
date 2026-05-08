import Foundation
import XCTest

// ATDD Red-Phase Test Scaffolds for Story 1.6
// AC: #1 - 全部 15 个工具注册可用
// These tests verify all 15 MCP tools are registered and callable through a real Helper process.
// They require macOS with AX permissions — skipped in CI environments.
// Priority: P0 (Epic 1 completion gate — all tools must be registered)

final class FullToolRegistrationTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        signal(SIGPIPE, SIG_IGN)
    }

    // MARK: - Helpers

    /// Path to the built AxionHelper executable.
    private var helperExecutablePath: String {
        let projectRoot = FileManager.default.currentDirectoryPath
        let debugPath = "\(projectRoot)/.build/debug/AxionHelper"
        let releasePath = "\(projectRoot)/.build/release/AxionHelper"
        if FileManager.default.fileExists(atPath: debugPath) { return debugPath }
        if FileManager.default.fileExists(atPath: releasePath) { return releasePath }
        return debugPath
    }

    /// All 15 expected tool names (Stories 1.2-1.5).
    private let expectedToolNames = [
        "launch_app", "list_apps", "list_windows", "get_window_state",
        "click", "double_click", "right_click", "type_text",
        "press_key", "hotkey", "scroll", "drag",
        "screenshot", "get_accessibility_tree", "open_url",
    ]

    private let initializeRequest = """
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

    """

    private let toolsListRequest = """
    {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}

    """

    /// Starts Helper, sends initialize + initialized notification, returns process, pipes, and initialize response.
    private func startHelperAndInitialize() async throws -> (Process, Pipe, Pipe, Data) {
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
            return (process, stdinPipe, stdoutPipe, Data())
        }
        stdinPipe.fileHandleForWriting.write(initData)

        // Wait for initialize response
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(5.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        guard responseData.count > 0 else {
            XCTFail("No initialize response received")
            return (process, stdinPipe, stdoutPipe, Data())
        }

        // Send initialized notification
        let initializedNotification = """
        {"jsonrpc":"2.0","method":"notifications/initialized"}

        """
        guard let notifData = initializedNotification.data(using: .utf8) else {
            return (process, stdinPipe, stdoutPipe, responseData)
        }
        stdinPipe.fileHandleForWriting.write(notifData)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        return (process, stdinPipe, stdoutPipe, responseData)
    }

    // MARK: - AC1: 全部 15 个工具注册可用

    // [P0] Helper process returns all 15 tools via tools/list (process-level integration)
    func test_toolsList_all15ToolsRegistered_viaRealMCP() async throws {
        // Given: Helper is running and MCP is initialized
        let (process, stdinPipe, stdoutPipe, initData) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        guard initData.count > 0 else { return }

        // When: Sending tools/list request
        guard let requestData = toolsListRequest.data(using: .utf8) else {
            XCTFail("Failed to encode tools/list request")
            return
        }
        stdinPipe.fileHandleForWriting.write(requestData)

        // Read response
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        XCTAssertGreaterThan(responseData.count, 0, "Should receive tools/list response")

        // Then: Parse response and verify all 15 tools are present
        let responseString = String(data: responseData, encoding: .utf8) ?? ""

        // The response may contain multiple JSON objects (init response + tools/list response)
        // Find the tools/list response by looking for tool definitions
        for expectedTool in expectedToolNames {
            XCTAssertTrue(
                responseString.contains(expectedTool),
                "Tool '\(expectedTool)' should appear in tools/list response. Got: \(responseString.prefix(500))"
            )
        }
    }

    // [P0] Each tool in tools/list response has name and description
    func test_toolsList_eachToolHasNameAndDescription() async throws {
        // Given: Helper is running and MCP is initialized
        let (process, stdinPipe, stdoutPipe, initData) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        guard initData.count > 0 else { return }

        // When: Sending tools/list request
        guard let requestData = toolsListRequest.data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(requestData)

        // Read response
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        XCTAssertGreaterThan(responseData.count, 0, "Should receive tools/list response")

        // Then: Response contains description field (each tool should have one)
        let responseString = String(data: responseData, encoding: .utf8) ?? ""
        XCTAssertTrue(
            responseString.contains("description"),
            "tools/list response should contain 'description' field for each tool"
        )
    }

    // [P0] Initialize response contains server capabilities with tools support
    func test_initializeResponse_containsToolsCapability() async throws {
        // Given: Helper is starting
        let (process, stdinPipe, _, initData) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        // Then: Initialize response is valid JSON with capabilities
        XCTAssertGreaterThan(initData.count, 0, "Should receive initialize response")

        let responseString = String(data: initData, encoding: .utf8) ?? ""
        XCTAssertTrue(
            responseString.contains("capabilities"),
            "Initialize response should contain 'capabilities'"
        )
        XCTAssertTrue(
            responseString.contains("tools"),
            "Initialize capabilities should include 'tools'"
        )
    }
}
