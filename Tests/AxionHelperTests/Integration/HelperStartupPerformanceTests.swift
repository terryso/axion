import Foundation
import XCTest

// ATDD Red-Phase Test Scaffolds for Story 1.6
// AC: #3 - Helper MCP 启动就绪性能 (NFR2: < 500ms)
// These tests measure AxionHelper process startup time from launch to MCP initialize response.
// They require macOS with AX permissions and a built AxionHelper binary.
// Priority: P0 (NFR2 verification — critical performance gate)

final class HelperStartupPerformanceTests: XCTestCase {

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

    private func makeHelperProcess() -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperExecutablePath)
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    private let initializeRequest = """
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"TestClient","version":"1.0.0"}}}

    """

    // MARK: - AC3: NFR2 — Helper startup to MCP ready < 500ms

    // [P0] Helper startup to MCP initialize response is under 500ms (NFR2)
    func test_helperStartup_initializeResponseTime_under500ms() async throws {
        // Given: AxionHelper is built
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            throw XCTSkip("AxionHelper not built. Run `swift build` first.")
        }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stdoutPipe = process.standardOutput as! Pipe

        // When: Starting process and measuring time to MCP initialize response
        let startTime = Date()
        try process.run()

        try await Task.sleep(nanoseconds: 100_000_000) // 100ms settle

        guard let requestData = initializeRequest.data(using: .utf8) else {
            XCTFail("Failed to encode initialize request")
            return
        }
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
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Response received and startup time < 500ms (NFR2)
        XCTAssertGreaterThan(responseData.count, 0, "Should receive MCP initialize response")
        XCTAssertLessThan(
            elapsed, 0.5,
            "AxionHelper startup to initialize response should be < 500ms (NFR2), took \(String(format: "%.3f", elapsed))s"
        )

        // Clean up
        stdinPipe.fileHandleForWriting.closeFile()
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate() }
    }

    // [P1] Consecutive restarts all meet NFR2
    func test_helperStartup_consecutiveRestarts_meetNFR2() async throws {
        // Given: AxionHelper is built
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else {
            throw XCTSkip("AxionHelper not built. Run `swift build` first.")
        }

        // When: Starting and stopping Helper 3 times
        var measurements: [TimeInterval] = []

        for _ in 0..<3 {
            let process = makeHelperProcess()
            let stdinPipe = process.standardInput as! Pipe
            let stdoutPipe = process.standardOutput as! Pipe

            let startTime = Date()
            try process.run()

            try await Task.sleep(nanoseconds: 100_000_000)

            guard let requestData = initializeRequest.data(using: .utf8) else { continue }
            stdinPipe.fileHandleForWriting.write(requestData)

            let readHandle = stdoutPipe.fileHandleForReading
            var responseData = Data()
            let deadline = Date().addingTimeInterval(3.0)
            while responseData.isEmpty && Date() < deadline {
                let available = readHandle.availableData
                if !available.isEmpty { responseData.append(available) }
                else { try await Task.sleep(nanoseconds: 50_000_000) }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            if responseData.count > 0 { measurements.append(elapsed) }

            // Clean up
            stdinPipe.fileHandleForWriting.closeFile()
            let exitDeadline = Date().addingTimeInterval(3.0)
            while process.isRunning && Date() < exitDeadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning { process.terminate() }
        }

        // Then: All starts should meet NFR2
        XCTAssertGreaterThanOrEqual(measurements.count, 2, "Should have at least 2 successful measurements")
        for (index, elapsed) in measurements.enumerated() {
            XCTAssertLessThan(
                elapsed, 0.5,
                "Restart #\(index + 1) took \(String(format: "%.3f", elapsed))s, exceeding NFR2 (500ms)"
            )
        }
    }
}
