import Testing
import Foundation
import Darwin

// ATDD Red-Phase Test Scaffolds for Story 1.2
// AC: #1 - MCP initialize 响应（进程级集成）
// AC: #4 - EOF 优雅退出（进程级集成）
// These tests launch AxionHelper as an actual Process and communicate via stdin/stdout JSON-RPC.
// This is 方案 B from the story's test strategy: process-level integration tests.
// Priority: P0 (smoke test for the complete MCP stdio communication)

@Suite("Helper Process Smoke")
struct HelperProcessSmokeTests {

    init() {
        // Ignore SIGPIPE to prevent test runner crash when child process pipe breaks
        signal(SIGPIPE, SIG_IGN)
    }

    // MARK: - Helpers

    /// Path to the built AxionHelper executable.
    /// Assumes `swift build` has been run before tests execute.
    private var helperExecutablePath: String {
        // SPM builds executables to .build/debug/ for debug configuration
        let projectRoot = FileManager.default.currentDirectoryPath
        // Try debug build first, then release
        let debugPath = "\(projectRoot)/.build/debug/AxionHelper"
        let releasePath = "\(projectRoot)/.build/release/AxionHelper"

        if FileManager.default.fileExists(atPath: debugPath) {
            return debugPath
        } else if FileManager.default.fileExists(atPath: releasePath) {
            return releasePath
        }
        return debugPath // Return default, test will fail with clear error
    }

    /// Creates a Process configured to run AxionHelper with piped stdin/stdout.
    private func makeHelperProcess() -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperExecutablePath)
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    // MARK: - AC1: MCP initialize 响应（进程级）

    // [P0] AxionHelper 进程可以通过 MCP JSON-RPC 初始化
    @Test("helper process initialize responds")
    func helperProcessInitializeResponds() async throws {
        // Given: AxionHelper 已编译
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            Issue.record("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
            return
        }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stdoutPipe = process.standardOutput as! Pipe

        // When: 启动进程并发送 MCP initialize 请求
        try process.run()

        // Brief pause to let the process start
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let initializeRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

        """
        guard let requestData = initializeRequest.data(using: .utf8) else {
            Issue.record("Failed to encode initialize request")
            return
        }
        stdinPipe.fileHandleForWriting.write(requestData)

        // Then: 读取响应（轮询直到有数据或超时）
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(5.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty {
                responseData.append(available)
            } else {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }

        #expect(responseData.count > 0)

        // Parse response as JSON
        let responseDataObj = try JSONSerialization.jsonObject(with: responseData)
        let responseDict = try #require(responseDataObj as? [String: Any])

        #expect(responseDict["jsonrpc"] as? String == "2.0")
        #expect(responseDict["id"] as? Int == 1)
        #expect(responseDict["result"] != nil)

        // Clean up: close stdin to let process exit gracefully
        stdinPipe.fileHandleForWriting.closeFile()
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - AC4: EOF 优雅退出

    // [P0] stdin EOF 时 AxionHelper 优雅退出，无崩溃
    @Test("helper process graceful exit on EOF")
    func helperProcessGracefulExitOnEOF() async throws {
        // Given: AxionHelper 进程正在运行
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            Issue.record("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
            return
        }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stderrPipe = process.standardError as! Pipe

        // When: 启动进程
        try process.run()
        #expect(process.isRunning)

        // Give the process a moment to initialize
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // When: 关闭 stdin（发送 EOF）
        stdinPipe.fileHandleForWriting.closeFile()

        // Then: Helper 在合理时间内退出，无崩溃
        // Wait up to 3 seconds for process to exit
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms polling
        }

        #expect(!process.isRunning)

        // Verify exit code is 0 (clean exit, not crash)
        let exitCode = process.terminationStatus
        #expect(exitCode == 0)

        // Verify no crash signals
        let terminationReason = process.terminationReason
        #expect(terminationReason == .exit)

        // Verify stderr doesn't contain crash indicators
        let stderrData = stderrPipe.fileHandleForReading.availableData
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
        #expect(!stderrOutput.contains("Fatal error"))
        #expect(!stderrOutput.contains("Segmentation fault"))
    }

    // [P1] Helper exits cleanly after MCP initialize → stdin EOF sequence (AC5: Helper 随 CLI 退出)
    @Test("helper process initialize then EOF exits cleanly")
    func helperProcessInitializeThenEOFExitsCleanly() async throws {
        // Given: AxionHelper 已编译
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            Issue.record("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
            return
        }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stdoutPipe = process.standardOutput as! Pipe

        // When: 启动进程
        try process.run()

        try await Task.sleep(nanoseconds: 200_000_000) // 200ms settle

        // Send MCP initialize
        let initializeRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

        """
        guard let requestData = initializeRequest.data(using: .utf8) else {
            Issue.record("Failed to encode initialize request")
            return
        }
        stdinPipe.fileHandleForWriting.write(requestData)

        // Verify initialize response
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let initDeadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < initDeadline {
            let available = readHandle.availableData
            if !available.isEmpty { responseData.append(available) }
            else { try await Task.sleep(nanoseconds: 50_000_000) }
        }

        #expect(responseData.count > 0)

        // Verify the response is valid JSON-RPC with result
        let responseObj = try JSONSerialization.jsonObject(with: responseData)
        let responseDict = try #require(responseObj as? [String: Any])
        #expect(responseDict["result"] != nil)
        #expect(responseDict["id"] as? Int == 1)

        // When: 关闭 stdin（模拟 CLI 退出）
        stdinPipe.fileHandleForWriting.closeFile()

        // Then: Helper 进程退出，无残留
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(!process.isRunning)
        #expect(process.terminationStatus == 0)
        #expect(process.terminationReason == .exit)
    }

    // [P1] AxionHelper 启动响应时间满足 NFR2 (< 500ms)
    @Test("helper process startup time meets NFR2")
    func helperProcessStartupTimeMeetsNFR2() async throws {
        // Given: AxionHelper 已编译
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            Issue.record("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
            return
        }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stdoutPipe = process.standardOutput as! Pipe

        // When: 启动进程并发送 initialize，测量到收到响应的时间
        let startTime = Date()
        try process.run()

        let initializeRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

        """
        guard let requestData = initializeRequest.data(using: .utf8) else {
            Issue.record("Failed to encode initialize request")
            return
        }

        // Brief pause to let the process start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms 等待

        stdinPipe.fileHandleForWriting.write(requestData)

        // Poll for response
        let readHandle = stdoutPipe.fileHandleForReading
        var responseData = Data()
        let deadline = Date().addingTimeInterval(3.0)
        while responseData.isEmpty && Date() < deadline {
            let available = readHandle.availableData
            if !available.isEmpty {
                responseData.append(available)
            } else {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Then: NFR2 要求 AxionHelper 启动到 MCP 连接就绪 < 500ms
        #expect(responseData.count > 0)
        #expect(elapsed < 0.5)

        // Clean up
        stdinPipe.fileHandleForWriting.closeFile()
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning {
            process.terminate()
        }
    }
}
