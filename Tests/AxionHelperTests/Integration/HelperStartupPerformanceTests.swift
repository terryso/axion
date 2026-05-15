import Foundation
import Testing

@Suite("Helper Startup Performance")
struct HelperStartupPerformanceTests {

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

    @Test("helper startup initialize response time under 500ms")
    func helperStartupInitializeResponseTimeUnder500ms() async throws {
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else { return }

        let process = makeHelperProcess()
        let stdinPipe = process.standardInput as! Pipe
        let stdoutPipe = process.standardOutput as! Pipe

        let startTime = Date()
        try process.run()

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let requestData = initializeRequest.data(using: .utf8) else {
            Issue.record("Failed to encode initialize request")
            return
        }
        stdinPipe.fileHandleForWriting.write(requestData)

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

        #expect(responseData.count > 0, "Should receive MCP initialize response")
        #expect(elapsed < 0.5,
                "AxionHelper startup to initialize response should be < 500ms (NFR2), took \(String(format: "%.3f", elapsed))s")

        stdinPipe.fileHandleForWriting.closeFile()
        let exitDeadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < exitDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate() }
    }

    @Test("helper startup consecutive restarts meet NFR2")
    func helperStartupConsecutiveRestartsMeetNFR2() async throws {
        guard FileManager.default.fileExists(atPath: helperExecutablePath) else { return }

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

            stdinPipe.fileHandleForWriting.closeFile()
            let exitDeadline = Date().addingTimeInterval(3.0)
            while process.isRunning && Date() < exitDeadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning { process.terminate() }
        }

        #expect(measurements.count >= 2, "Should have at least 2 successful measurements")
        for (index, elapsed) in measurements.enumerated() {
            #expect(elapsed < 0.5,
                    "Restart #\(index + 1) took \(String(format: "%.3f", elapsed))s, exceeding NFR2 (500ms)")
        }
    }
}
