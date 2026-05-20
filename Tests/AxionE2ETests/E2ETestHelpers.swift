import Foundation
import Testing

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

// MARK: - E2E Helper Fixture

/// Manages a real Helper process for E2E tests.
/// Reuses the same pattern as RunEngineIntegrationTests.
final class E2EHelperFixture {
    private(set) var manager: HelperProcessManager?
    private(set) var mcpClient: AxionCore.MCPClientProtocol?
    let tempDir: URL

    init() throws {
        self.tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AxionE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    /// Starts the Helper process. Returns false if unavailable (caller should skip).
    @discardableResult
    func setUpHelper() async throws -> Bool {
        let mgr = HelperProcessManager()
        do {
            try await mgr.start()
        } catch {
            return false
        }

        let running = await mgr.isRunning()
        #expect(running, "Helper should be running after start()")

        self.manager = mgr
        self.mcpClient = RealMCPAdapter(manager: mgr)
        return true
    }

    func tearDown() async {
        if let manager {
            await manager.stop()
        }
        self.manager = nil
        self.mcpClient = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Adapter

    struct RealMCPAdapter: AxionCore.MCPClientProtocol {
        private let manager: HelperProcessManager

        init(manager: HelperProcessManager) {
            self.manager = manager
        }

        func callTool(name: String, arguments: [String: AxionCore.Value]) async throws -> String {
            return try await manager.callTool(name: name, arguments: arguments)
        }

        func listTools() async throws -> [String] {
            return try await manager.listTools()
        }
    }
}

// MARK: - Mock Agent Stream

/// Simulates `Agent.stream()` by yielding a predefined sequence of SDKMessages.
func mockAgentStream(messages: [SDKMessage]) -> AsyncStream<SDKMessage> {
    AsyncStream { continuation in
        for message in messages {
            continuation.yield(message)
        }
        continuation.finish()
    }
}

// MARK: - Capturing Output

/// Thread-safe lines buffer shared between CapturingOutput and TerminalOutput's closure.
private final class LinesBuffer: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// A TerminalOutput substitute that captures all written strings for assertions.
final class CapturingOutput {
    private let buffer = LinesBuffer()
    let output: TerminalOutput

    init() {
        let buffer = self.buffer
        self.output = TerminalOutput(write: { buffer.append($0) })
    }

    var lines: [String] { buffer.all }

    func contains(_ substring: String) -> Bool {
        lines.contains(where: { $0.contains(substring) })
    }

    var allOutput: String {
        lines.joined(separator: "\n")
    }
}

// MARK: - Capturing JSON Output

/// Captures JSON output from SDKJSONOutputHandler.
final class CapturingJSONOutput {
    private(set) var jsonStrings: [String] = []
    private let lock = NSLock()

    var lastJSON: String? {
        lock.lock()
        defer { lock.unlock() }
        return jsonStrings.last
    }

    var write: (String) -> Void {
        return { [weak self] text in
            self?.lock.lock()
            self?.jsonStrings.append(text)
            self?.lock.unlock()
        }
    }
}

// MARK: - Common SDKMessage Factories

enum E2EMessages {
    static func assistant(_ text: String) -> SDKMessage {
        .assistant(.init(text: text, model: "mock-model", stopReason: "end_turn"))
    }

    static func toolUse(_ tool: String, id: String = "tu-1", input: String = "{}") -> SDKMessage {
        .toolUse(.init(toolName: tool, toolUseId: id, input: input))
    }

    static func toolResult(id: String = "tu-1", content: String, isError: Bool = false) -> SDKMessage {
        .toolResult(.init(toolUseId: id, content: content, isError: isError))
    }

    static func partial(_ text: String) -> SDKMessage {
        .partialMessage(.init(text: text))
    }

    static func successResult(text: String = "Done", turns: Int = 1, durationMs: Int = 500) -> SDKMessage {
        .result(.init(
            subtype: .success,
            text: text,
            usage: nil,
            numTurns: turns,
            durationMs: durationMs
        ))
    }

    static func errorResult(text: String = "Max turns exceeded", turns: Int = 3) -> SDKMessage {
        .result(.init(
            subtype: .errorMaxTurns,
            text: text,
            usage: nil,
            numTurns: turns,
            durationMs: 3000
        ))
    }
}

// MARK: - E2E Pipeline Runner

/// Runs the full message-handling pipeline (as used in RunCommand.run()) with mock agent messages.
/// This tests the output handler + trace recording path without a real LLM.
struct E2EPipelineRunner {
    let outputHandler: SDKMessageOutputHandler
    let tracer: TraceRecorder?

    func run(messages: [SDKMessage]) async {
        let stream = mockAgentStream(messages: messages)
        for await message in stream {
            outputHandler.handleMessage(message)
            await recordToTrace(message: message)
        }
        outputHandler.displayCompletion()
    }

    private func recordToTrace(message: SDKMessage) async {
        guard let tracer else { return }
        switch message {
        case .assistant(let data):
            await tracer.record(event: "assistant_message", payload: [
                "text": String(data.text.prefix(200)),
                "model": data.model,
                "stopReason": data.stopReason,
            ])
        case .toolUse(let data):
            await tracer.record(event: "tool_use", payload: [
                "tool": data.toolName,
                "toolUseId": data.toolUseId,
            ])
        case .toolResult(let data):
            await tracer.record(event: "tool_result", payload: [
                "toolUseId": data.toolUseId,
                "isError": data.isError,
                "content": String(data.content.prefix(200)),
            ])
        case .result(let data):
            await tracer.record(event: "result", payload: [
                "subtype": data.subtype.rawValue,
                "numTurns": data.numTurns,
                "durationMs": data.durationMs,
            ])
        case .partialMessage:
            break
        default:
            break
        }
    }
}
