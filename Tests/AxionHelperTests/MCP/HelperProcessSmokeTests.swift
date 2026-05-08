import XCTest
import Foundation
import Darwin

// ATDD Red-Phase Test Scaffolds for Story 1.2
// AC: #1 - MCP initialize 响应（进程级集成）
// AC: #4 - EOF 优雅退出（进程级集成）
// These tests launch AxionHelper as an actual Process and communicate via stdin/stdout JSON-RPC.
// This is 方案 B from the story's test strategy: process-level integration tests.
// Priority: P0 (smoke test for the complete MCP stdio communication)

final class HelperProcessSmokeTests: XCTestCase {

    override class func setUp() {
        super.setUp()
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
    func test_helperProcess_initializeResponds() async throws {
        // Given: AxionHelper 已编译
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            XCTFail("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
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
            XCTFail("Failed to encode initialize request")
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

        XCTAssertGreaterThan(responseData.count, 0, "Should receive response from AxionHelper")

        // Parse response as JSON
        let responseDataObj = try JSONSerialization.jsonObject(with: responseData)
        let responseDict = try XCTUnwrap(responseDataObj as? [String: Any])

        XCTAssertEqual(responseDict["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(responseDict["id"] as? Int, 1)
        XCTAssertNotNil(responseDict["result"], "Response should contain 'result' field")

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
    func test_helperProcess_gracefulExitOnEOF() async throws {
        // Given: AxionHelper 进程正在运行
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            XCTFail("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
            return
        }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stderrPipe = process.standardError as! Pipe

        // When: 启动进程
        try process.run()
        XCTAssertTrue(process.isRunning, "AxionHelper should be running after launch")

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

        XCTAssertFalse(process.isRunning, "AxionHelper should exit within 3 seconds after stdin EOF")

        // Verify exit code is 0 (clean exit, not crash)
        let exitCode = process.terminationStatus
        XCTAssertEqual(exitCode, 0, "AxionHelper should exit with code 0 (graceful), got \(exitCode)")

        // Verify no crash signals
        let terminationReason = process.terminationReason
        XCTAssertEqual(
            terminationReason, .exit,
            "AxionHelper should terminate normally (.exit), not by signal (.uncaughtSignal). Got: \(terminationReason)"
        )

        // Verify stderr doesn't contain crash indicators
        let stderrData = stderrPipe.fileHandleForReading.availableData
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
        XCTAssertFalse(
            stderrOutput.contains("Fatal error"),
            "No fatal error in stderr. Output: \(stderrOutput)"
        )
        XCTAssertFalse(
            stderrOutput.contains("Segmentation fault"),
            "No segfault in stderr. Output: \(stderrOutput)"
        )
    }

    // [P1] Helper exits cleanly after MCP initialize → stdin EOF sequence (AC5: Helper 随 CLI 退出)
    func test_helperProcess_initializeThenEOF_exitsCleanly() async throws {
        // Given: AxionHelper 已编译
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            XCTFail("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
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
            XCTFail("Failed to encode initialize request")
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

        XCTAssertGreaterThan(responseData.count, 0, "Should receive initialize response")

        // Verify the response is valid JSON-RPC with result
        let responseObj = try JSONSerialization.jsonObject(with: responseData)
        let responseDict = try XCTUnwrap(responseObj as? [String: Any])
        XCTAssertNotNil(responseDict["result"], "Initialize should return result")
        XCTAssertEqual(responseDict["id"] as? Int, 1, "Response ID should match request")

        // When: 关闭 stdin（模拟 CLI 退出）
        stdinPipe.fileHandleForWriting.closeFile()

        // Then: Helper 进程退出，无残留
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertFalse(process.isRunning, "Helper should exit after stdin EOF (no residual process)")
        XCTAssertEqual(process.terminationStatus, 0, "Helper should exit cleanly with code 0")
        XCTAssertEqual(process.terminationReason, .exit, "Helper should terminate normally, not by signal")
    }

    // [P1] AxionHelper 启动响应时间满足 NFR2 (< 500ms)
    func test_helperProcess_startupTime_meetsNFR2() async throws {
        // Given: AxionHelper 已编译
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            XCTFail("AxionHelper not found at \(helperExecutablePath). Run `swift build` first.")
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
            XCTFail("Failed to encode initialize request")
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
        XCTAssertGreaterThan(responseData.count, 0, "Should receive response from AxionHelper")
        XCTAssertLessThan(
            elapsed, 0.5,
            "AxionHelper startup to initialize response should be < 500ms (NFR2), took \(elapsed)s"
        )

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
