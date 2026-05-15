import Foundation
import Testing

@Suite("Single Operation Performance")
struct SingleOperationPerformanceTests {

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

    private let initializeRequest = """
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

    """

    private let listAppsRequest = """
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}

    """

    private func startHelperAndInitialize() async throws -> (Process, Pipe, Pipe) {
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            return (Process(), Pipe(), Pipe())
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
            return (process, stdinPipe, stdoutPipe)
        }
        stdinPipe.fileHandleForWriting.write(initData)

        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        guard responseData.count > 0 else {
            return (process, stdinPipe, stdoutPipe)
        }

        return (process, stdinPipe, stdoutPipe)
    }

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

    @Test("list_apps response time under 200ms")
    func listAppsResponseTimeUnder200ms() async throws {
        let (process, stdinPipe, stdoutPipe) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        guard let requestData = listAppsRequest.data(using: .utf8) else {
            Issue.record("Failed to encode list_apps request")
            return
        }

        let startTime = Date()
        stdinPipe.fileHandleForWriting.write(requestData)
        let responseData = try await readResponse(from: stdoutPipe, timeout: 3.0)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(responseData.count > 0, "Should receive list_apps response")

        let responseString = String(data: responseData, encoding: .utf8) ?? ""
        #expect(
            responseString.contains("list_apps") || responseString.contains("result"),
            "Response should contain tool result. Got: \(responseString.prefix(200))"
        )

        #expect(elapsed < 0.2,
                "list_apps round-trip should be < 200ms (NFR3), took \(String(format: "%.3f", elapsed))s")
    }

    @Test("get_window_state response time under 200ms")
    func getWindowStateResponseTimeUnder200ms() async throws {
        let (process, stdinPipe, stdoutPipe) = try await startHelperAndInitialize()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        let getWindowStateRequest = """
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_window_state","arguments":{"window_id":1}}}

        """

        guard let requestData = getWindowStateRequest.data(using: .utf8) else {
            Issue.record("Failed to encode get_window_state request")
            return
        }

        let startTime = Date()
        stdinPipe.fileHandleForWriting.write(requestData)
        let responseData = try await readResponse(from: stdoutPipe, timeout: 3.0)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(responseData.count > 0, "Should receive get_window_state response")

        #expect(elapsed < 0.2,
                "get_window_state round-trip should be < 200ms (NFR3), took \(String(format: "%.3f", elapsed))s")
    }
}
