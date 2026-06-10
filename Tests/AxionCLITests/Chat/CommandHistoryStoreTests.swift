import Testing
import Foundation

@testable import AxionCLI

// [P0] 基础设施验证 — CommandHistoryStore 跨会话历史持久化

@Suite("CommandHistoryStore")
struct CommandHistoryStoreTests {

    // MARK: - Helpers

    /// Create a store with in-memory file I/O for testing.
    private func makeStore(
        initialContent: String? = nil
    ) -> (store: CommandHistoryStore, fileContent: MockFile) {
        let mock = MockFile(content: initialContent)
        let store = CommandHistoryStore(
            readFile: { _ in mock.content },
            appendFile: { _, line in mock.content = (mock.content ?? "") + line + "\n" },
            writeFile: { _, content in mock.content = content }
        )
        return (store, mock)
    }

    /// A simple mutable wrapper for mock file content.
    final class MockFile: @unchecked Sendable {
        var content: String?
        init(content: String? = nil) { self.content = content }
    }

    private func makeJSONLine(_ text: String, ts: String = "2026-06-10T00:00:00Z") -> String {
        let obj: [String: String] = ["text": text, "ts": ts]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: .sortedKeys)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Load Tests

    @Test("load returns empty array for missing file")
    func load_missingFile() {
        let (store, _) = makeStore(initialContent: nil)
        let result = store.load(filePath: "/dev/null")
        #expect(result.isEmpty)
    }

    @Test("load returns empty array for empty file")
    func load_emptyFile() {
        let (store, _) = makeStore(initialContent: "")
        let result = store.load(filePath: "/dev/null")
        #expect(result.isEmpty)
    }

    @Test("load parses valid JSONL entries")
    func load_validEntries() {
        let content = """
        {"text":"hello","ts":"2026-06-10T10:00:00Z"}
        {"text":"world","ts":"2026-06-10T10:01:00Z"}
        {"text":"test","ts":"2026-06-10T10:02:00Z"}
        """
        let (store, _) = makeStore(initialContent: content)
        let result = store.load(filePath: "/dev/null")
        #expect(result == ["hello", "world", "test"])
    }

    @Test("load skips corrupted lines")
    func load_corruptedLines() {
        let content = """
        {"text":"valid","ts":"2026-06-10T10:00:00Z"}
        NOT_JSON
        {"missing_ts":"yes"}
        {"text":"also valid","ts":"2026-06-10T10:01:00Z"}
        """
        let (store, _) = makeStore(initialContent: content)
        let result = store.load(filePath: "/dev/null")
        #expect(result == ["valid", "also valid"])
    }

    @Test("load deduplicates keeping most recent occurrence")
    func load_dedupKeepsMostRecent() {
        let content = """
        {"text":"repeat","ts":"2026-06-10T10:00:00Z"}
        {"text":"unique","ts":"2026-06-10T10:01:00Z"}
        {"text":"repeat","ts":"2026-06-10T10:02:00Z"}
        """
        let (store, _) = makeStore(initialContent: content)
        let result = store.load(filePath: "/dev/null")
        // Both "repeat" entries are same text, but dedup keeps most recent (last)
        // After dedup: unique, repeat (most recent)
        #expect(result == ["unique", "repeat"])
    }

    @Test("load dedup is case-insensitive")
    func load_dedupCaseInsensitive() {
        let content = """
        {"text":"Hello","ts":"2026-06-10T10:00:00Z"}
        {"text":"hello","ts":"2026-06-10T10:01:00Z"}
        """
        let (store, _) = makeStore(initialContent: content)
        let result = store.load(filePath: "/dev/null")
        #expect(result == ["hello"])
    }

    @Test("load trims to max capacity keeping most recent")
    func load_trimsToMaxCapacity() {
        var lines: [String] = []
        for i in 0..<1100 {
            lines.append(makeJSONLine("cmd-\(i)", ts: "2026-06-10T\(i / 3600):\(i % 60):00Z"))
        }
        let content = lines.joined(separator: "\n")

        let (store, _) = makeStore(initialContent: content)
        let result = store.load(filePath: "/dev/null")

        #expect(result.count == CommandHistoryStore.maxEntries)
        // Should keep the most recent entries (cmd-100 through cmd-1099)
        #expect(result.first == "cmd-100")
        #expect(result.last == "cmd-1099")
    }

    // MARK: - Append Tests

    @Test("append adds entry to file")
    func append_addsEntry() {
        let (store, mock) = makeStore(initialContent: nil)
        store.append(text: "new command", filePath: "/dev/null")

        let content = mock.content!
        #expect(content.contains("\"text\":\"new command\""))
        #expect(content.hasSuffix("\n"))
    }

    @Test("append creates valid JSONL")
    func append_validJSONL() {
        let (store, mock) = makeStore(initialContent: nil)
        store.append(text: "test", filePath: "/dev/null")

        let line = mock.content!.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = line.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: String]
        #expect(obj["text"] == "test")
        #expect(obj["ts"] != nil)
    }

    // MARK: - Compact Tests

    @Test("compact rewrites file when over capacity")
    func compact_rewritesWhenOverCapacity() {
        var lines: [String] = []
        for i in 0..<1100 {
            lines.append(makeJSONLine("cmd-\(i)", ts: "2026-06-10T00:\(String(format: "%02d", i % 60)):00Z"))
        }
        let content = lines.joined(separator: "\n")

        let (store, mock) = makeStore(initialContent: content)
        store.compact(filePath: "/dev/null")

        // After compact, should have exactly maxEntries lines
        let compacted = mock.content!
        let compactedLines = compacted.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(compactedLines.count == CommandHistoryStore.maxEntries)
    }

    @Test("compact does not rewrite when under capacity")
    func compact_noopWhenUnderCapacity() {
        let content = """
        {"text":"a","ts":"2026-06-10T10:00:00Z"}
        {"text":"b","ts":"2026-06-10T10:01:00Z"}
        """
        let (store, mock) = makeStore(initialContent: content)
        let originalContent = mock.content
        store.compact(filePath: "/dev/null")
        // writeFile should NOT have been called since entries < maxEntries
        #expect(mock.content == originalContent)
    }

    @Test("compact handles empty file")
    func compact_emptyFile() {
        let (store, mock) = makeStore(initialContent: "")
        store.compact(filePath: "/dev/null")
        #expect(mock.content == "")
    }

    // MARK: - Round-trip Tests

    @Test("load after append preserves entries")
    func roundTrip_appendAndLoad() {
        let (store, mock) = makeStore(initialContent: nil)
        store.append(text: "first", filePath: "/dev/null")
        store.append(text: "second", filePath: "/dev/null")

        // Create a new store reading from the same mock content
        let store2 = CommandHistoryStore(
            readFile: { _ in mock.content },
            appendFile: { _, _ in },
            writeFile: { _, _ in }
        )
        let loaded = store2.load(filePath: "/dev/null")
        #expect(loaded == ["first", "second"])
    }
}
