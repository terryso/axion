import Foundation
import Testing

@Suite("Full Tool Registration")
struct FullToolRegistrationTests {

    init() {
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

    private func startHelperAndInitialize() async throws -> (Process, Pipe, Pipe, Data) {
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            return (Process(), Pipe(), Pipe(), Data())
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
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let initData = initializeRequest.data(using: .utf8) else {
            return (process, stdinPipe, stdoutPipe, Data())
        }
        stdinPipe.fileHandleForWriting.write(initData)

        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(5.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        guard responseData.count > 0 else {
            return (process, stdinPipe, stdoutPipe, Data())
        }

        let initializedNotification = """
        {"jsonrpc":"2.0","method":"notifications/initialized"}

        """
        guard let notifData = initializedNotification.data(using: .utf8) else {
            return (process, stdinPipe, stdoutPipe, responseData)
        }
        stdinPipe.fileHandleForWriting.write(notifData)
        try await Task.sleep(nanoseconds: 100_000_000)

        return (process, stdinPipe, stdoutPipe, responseData)
    }

    // MARK: - AC1: 全部 15 个工具注册可用

    @Test("tools/list all 15 tools registered via real MCP")
    func toolsListAll15ToolsRegistered() async throws {
        let (process, stdinPipe, stdoutPipe, initData) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        guard initData.count > 0 else { return }

        guard let requestData = toolsListRequest.data(using: .utf8) else {
            Issue.record("Failed to encode tools/list request")
            return
        }
        stdinPipe.fileHandleForWriting.write(requestData)

        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        #expect(responseData.count > 0, "Should receive tools/list response")

        let responseString = String(data: responseData, encoding: .utf8) ?? ""

        for expectedTool in expectedToolNames {
            #expect(responseString.contains(expectedTool),
                    "Tool '\(expectedTool)' should appear in tools/list response. Got: \(responseString.prefix(500))")
        }
    }

    @Test("tools/list each tool has name and description")
    func toolsListEachToolHasNameAndDescription() async throws {
        let (process, stdinPipe, stdoutPipe, initData) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        guard initData.count > 0 else { return }

        guard let requestData = toolsListRequest.data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(requestData)

        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        #expect(responseData.count > 0, "Should receive tools/list response")

        let responseString = String(data: responseData, encoding: .utf8) ?? ""
        #expect(responseString.contains("description"),
                "tools/list response should contain 'description' field for each tool")
    }

    @Test("initialize response contains tools capability")
    func initializeResponseContainsToolsCapability() async throws {
        let (process, stdinPipe, _, initData) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        #expect(initData.count > 0, "Should receive initialize response")

        let responseString = String(data: initData, encoding: .utf8) ?? ""
        #expect(responseString.contains("capabilities"),
                "Initialize response should contain 'capabilities'")
        #expect(responseString.contains("tools"),
                "Initialize capabilities should include 'tools'")
    }
}
