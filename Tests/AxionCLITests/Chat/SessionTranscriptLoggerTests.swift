import Testing
import Foundation

@testable import AxionCLI

// [P0] 基础设施验证 — SessionTranscriptLogger 会话转录持久化

@Suite("SessionTranscriptLogger")
struct SessionTranscriptLoggerTests {

    // MARK: - Helpers

    /// Mutable file content for testing.
    final class MockFile: @unchecked Sendable {
        var lines: [String] = []
    }

    /// Create a logger with in-memory I/O.
    private func makeLogger() -> (logger: SessionTranscriptLogger, file: MockFile) {
        let mock = MockFile()
        let logger = SessionTranscriptLogger(
            appendFn: { _, line in mock.lines.append(line) },
            ensureDirFn: { _ in }
        )
        return (logger, mock)
    }

    private let testDir = "/tmp/axion-test-sessions"
    private let testSessionId = "chat-abcd1234"

    // MARK: - Transcript Path

    @Test("transcriptPath returns correct file path")
    func transcriptPath_correctPath() {
        let path = SessionTranscriptLogger.transcriptPath(
            sessionId: "chat-abc",
            dirPath: "/home/user/.axion/sessions"
        )
        #expect(path == "/home/user/.axion/sessions/chat-abc.jsonl")
    }

    // MARK: - Session Lifecycle

    @Test("open writes session_start entry with model and cwd")
    func open_writesSessionStart() {
        let (logger, file) = makeLogger()
        logger.open(
            sessionId: testSessionId,
            dirPath: testDir,
            model: "claude-sonnet-4-20250514",
            cwd: "/home/user/project"
        )

        #expect(file.lines.count == 1)
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry != nil)
        #expect(entry?.type == .sessionStart)
        #expect(entry?.content == "session started")
        #expect(entry?.metadata?["model"] == "claude-sonnet-4-20250514")
        #expect(entry?.metadata?["cwd"] == "/home/user/project")
    }

    @Test("close writes session_end entry with stats")
    func close_writesSessionEnd() {
        let (logger, file) = makeLogger()
        logger.close(
            sessionId: testSessionId,
            dirPath: testDir,
            turns: 5,
            totalTokens: 12345,
            durationMs: 30000
        )

        #expect(file.lines.count == 1)
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry != nil)
        #expect(entry?.type == .sessionEnd)
        #expect(entry?.metadata?["turns"] == "5")
        #expect(entry?.metadata?["total_tokens"] == "12345")
        #expect(entry?.metadata?["duration_ms"] == "30000")
    }

    // MARK: - User Input

    @Test("logUserInput writes user_input entry")
    func logUserInput_writesEntry() {
        let (logger, file) = makeLogger()
        logger.logUserInput("帮我写一个排序函数", sessionId: testSessionId, dirPath: testDir)

        #expect(file.lines.count == 1)
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry?.type == .userInput)
        #expect(entry?.content == "帮我写一个排序函数")
        #expect(entry?.metadata == nil)
    }

    // MARK: - Assistant Response

    @Test("logAssistant writes assistant entry with text")
    func logAssistant_writesEntry() {
        let (logger, file) = makeLogger()
        logger.logAssistant("好的，这是快速排序的实现：", sessionId: testSessionId, dirPath: testDir)

        #expect(file.lines.count == 1)
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry?.type == .assistant)
        #expect(entry?.content == "好的，这是快速排序的实现：")
    }

    @Test("logAssistant skips empty text")
    func logAssistant_skipsEmpty() {
        let (logger, file) = makeLogger()
        logger.logAssistant("", sessionId: testSessionId, dirPath: testDir)

        #expect(file.lines.isEmpty)
    }

    // MARK: - Tool Use

    @Test("logToolUse writes tool_use entry with tool metadata")
    func logToolUse_writesEntry() {
        let (logger, file) = makeLogger()
        logger.logToolUse(
            toolName: "bash",
            input: "{\"command\": \"ls -la\"}",
            sessionId: testSessionId,
            dirPath: testDir
        )

        #expect(file.lines.count == 1)
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry?.type == .toolUse)
        #expect(entry?.content == "{\"command\": \"ls -la\"}")
        #expect(entry?.metadata?["tool"] == "bash")
    }

    // MARK: - Tool Result

    @Test("logToolResult writes tool_result entry with metadata")
    func logToolResult_writesEntry() {
        let (logger, file) = makeLogger()
        logger.logToolResult(
            toolName: "bash",
            content: "file1.txt\nfile2.txt",
            isError: false,
            durationMs: 150,
            sessionId: testSessionId,
            dirPath: testDir
        )

        #expect(file.lines.count == 1)
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry?.type == .toolResult)
        #expect(entry?.content == "file1.txt\nfile2.txt")
        #expect(entry?.metadata?["tool"] == "bash")
        #expect(entry?.metadata?["duration_ms"] == "150")
        #expect(entry?.metadata?["error"] == nil)
    }

    @Test("logToolResult truncates long content")
    func logToolResult_truncatesLongContent() {
        let (logger, file) = makeLogger()
        let longContent = String(repeating: "x", count: 3000)
        logger.logToolResult(
            toolName: "read",
            content: longContent,
            isError: false,
            durationMs: nil,
            sessionId: testSessionId,
            dirPath: testDir
        )

        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry != nil)
        // Content should be truncated to 2000 chars + "…"
        #expect(entry?.content.count == 2001)
        #expect(entry?.content.hasSuffix("…") == true)
    }

    @Test("logToolResult marks error in metadata")
    func logToolResult_marksError() {
        let (logger, file) = makeLogger()
        logger.logToolResult(
            toolName: "bash",
            content: "command not found",
            isError: true,
            durationMs: nil,
            sessionId: testSessionId,
            dirPath: testDir
        )

        let entry = SessionTranscriptLogger.Entry.fromJSONLine(file.lines[0])
        #expect(entry?.metadata?["error"] == "true")
    }

    // MARK: - Entry JSON Serialization

    @Test("Entry toJSONLine produces valid JSONL")
    func entry_toJSONLine_validJSON() {
        let entry = SessionTranscriptLogger.Entry(
            type: .userInput,
            content: "hello world",
            ts: "2026-06-10T12:00:00Z",
            metadata: nil
        )
        let line = entry.toJSONLine()
        #expect(line != nil)

        let data = line!.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["type"] as? String == "user_input")
        #expect(obj["content"] as? String == "hello world")
        #expect(obj["ts"] as? String == "2026-06-10T12:00:00Z")
    }

    @Test("Entry fromJSONLine parses all fields correctly")
    func entry_fromJSONLine_parsesAll() {
        let json = """
        {"content":"test content","metadata":{"tool":"bash","duration_ms":"100"},"ts":"2026-06-10T12:00:00Z","type":"tool_use"}
        """
        let entry = SessionTranscriptLogger.Entry.fromJSONLine(json)
        #expect(entry != nil)
        #expect(entry?.type == .toolUse)
        #expect(entry?.content == "test content")
        #expect(entry?.ts == "2026-06-10T12:00:00Z")
        #expect(entry?.metadata?["tool"] == "bash")
        #expect(entry?.metadata?["duration_ms"] == "100")
    }

    @Test("Entry fromJSONLine returns nil for invalid JSON")
    func entry_fromJSONLine_invalidJSON() {
        #expect(SessionTranscriptLogger.Entry.fromJSONLine("not json") == nil)
        #expect(SessionTranscriptLogger.Entry.fromJSONLine("") == nil)
        #expect(SessionTranscriptLogger.Entry.fromJSONLine("{\"no_type\": true}") == nil)
    }

    @Test("Entry fromJSONLine returns nil for unknown type")
    func entry_fromJSONLine_unknownType() {
        let json = """
        {"type":"unknown_type","content":"test","ts":"2026-06-10T12:00:00Z"}
        """
        #expect(SessionTranscriptLogger.Entry.fromJSONLine(json) == nil)
    }

    // MARK: - Round-trip

    @Test("Full session round-trip: open → input → assistant → tool → close")
    func roundTrip_fullSession() {
        let (logger, file) = makeLogger()

        // Simulate a full session
        logger.open(sessionId: testSessionId, dirPath: testDir, model: "claude-sonnet", cwd: "/tmp")
        logger.logUserInput("写一个 hello world", sessionId: testSessionId, dirPath: testDir)
        logger.logToolUse(toolName: "write", input: "{\"path\": \"hello.py\"}", sessionId: testSessionId, dirPath: testDir)
        logger.logAssistant("已创建 hello.py", sessionId: testSessionId, dirPath: testDir)
        logger.logToolResult(toolName: "write", content: "OK", isError: false, durationMs: 50, sessionId: testSessionId, dirPath: testDir)
        logger.close(sessionId: testSessionId, dirPath: testDir, turns: 1, totalTokens: 500, durationMs: 5000)

        #expect(file.lines.count == 6)

        // Verify order and types
        let types = file.lines.compactMap { SessionTranscriptLogger.Entry.fromJSONLine($0)?.type }
        #expect(types == [.sessionStart, .userInput, .toolUse, .assistant, .toolResult, .sessionEnd])
    }

    // MARK: - EntryType

    @Test("EntryType raw values match expected strings")
    func entryType_rawValues() {
        #expect(SessionTranscriptLogger.EntryType.userInput.rawValue == "user_input")
        #expect(SessionTranscriptLogger.EntryType.assistant.rawValue == "assistant")
        #expect(SessionTranscriptLogger.EntryType.toolUse.rawValue == "tool_use")
        #expect(SessionTranscriptLogger.EntryType.toolResult.rawValue == "tool_result")
        #expect(SessionTranscriptLogger.EntryType.system.rawValue == "system")
        #expect(SessionTranscriptLogger.EntryType.sessionStart.rawValue == "session_start")
        #expect(SessionTranscriptLogger.EntryType.sessionEnd.rawValue == "session_end")
    }

    // MARK: - Disabled Logger

    @Test("disabled logger does not write anything")
    func disabled_noWrites() {
        let logger = SessionTranscriptLogger.disabled
        // These should not crash or write anywhere
        logger.open(sessionId: "x", dirPath: "/dev/null", model: "test", cwd: "/tmp")
        logger.logUserInput("test", sessionId: "x", dirPath: "/dev/null")
        logger.logAssistant("response", sessionId: "x", dirPath: "/dev/null")
        logger.logToolUse(toolName: "bash", input: "ls", sessionId: "x", dirPath: "/dev/null")
        logger.close(sessionId: "x", dirPath: "/dev/null", turns: 0, totalTokens: 0, durationMs: 0)
        // No assertion needed — just verifying no crash
    }
}
