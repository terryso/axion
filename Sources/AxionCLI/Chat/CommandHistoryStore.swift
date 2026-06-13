import Foundation

/// Cross-session command history persistence.
///
/// Stores user input history in a JSONL file (`~/.axion/history.jsonl`) so that
/// Up/Down arrow history navigation works across sessions.
///
/// **Format:** Each line is a JSON object: `{"text": "...", "ts": "ISO8601"}`
///
/// **Deduplication:** On load, duplicate texts keep only the most recent entry.
///
/// **Capacity:** Max 1000 entries — oldest entries are trimmed when exceeded.
///
/// **I/O injection:** All file operations use injected closures for testability.
struct CommandHistoryStore: Sendable {

    /// Maximum number of history entries to retain.
    static let maxEntries = 1000

    // MARK: - I/O Closures (injected for testing)

    /// Reads the entire file as a string. Returns nil if the file does not exist.
    let readFile: @Sendable (String) -> String?

    /// Appends a string (with newline) to the file. Creates the file if needed.
    let appendFile: @Sendable (String, String) -> Void

    /// Writes the entire string to the file (atomically overwrites).
    let writeFile: @Sendable (String, String) -> Void

    // MARK: - Init

    /// Create with default file I/O (real filesystem).
    /// - Parameter filePath: Path to the JSONL history file.
    static func live(filePath: String = ConfigManager.historyFilePath) -> CommandHistoryStore {
        CommandHistoryStore(
            readFile: { path in try? String(contentsOfFile: path, encoding: .utf8) },
            appendFile: { path, line in
                guard let data = (line + "\n").data(using: .utf8) else { return }
                let fm = FileManager.default
                if !fm.fileExists(atPath: path) {
                    fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            },
            writeFile: { path, content in
                guard let data = content.data(using: .utf8) else { return }
                let fm = FileManager.default
                // Ensure parent directory exists
                let dir = (path as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        )
    }

    // MARK: - Public API

    /// Load history entries from disk, deduplicated and trimmed to max capacity.
    /// Returns entries in chronological order (oldest first).
    func load(filePath: String) -> [String] {
        guard let content = readFile(filePath), !content.isEmpty else {
            return []
        }

        var entries: [HistoryEntry] = []
        content.enumerateLines { line, _ in
            if let entry = HistoryEntry.fromJSON(line) {
                entries.append(entry)
            }
        }

        // Dedup: keep most recent occurrence of each text
        // Walk backward, add only first (most recent) occurrence of each text
        var seen = Set<String>()
        var deduped: [HistoryEntry] = []
        for entry in entries.reversed() {
            let key = entry.text.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(entry)
            }
        }
        deduped.reverse()  // Back to chronological order

        // Trim to max capacity (keep most recent)
        if deduped.count > Self.maxEntries {
            deduped = Array(deduped.suffix(Self.maxEntries))
        }

        return deduped.map(\.text)
    }

    /// Count slash command/skill invocations within the recent time window.
    ///
    /// Unlike `load(filePath:)`, this intentionally uses raw history entries
    /// instead of deduplicated history so ranking reflects actual usage.
    func recentSlashUsageCounts(
        filePath: String,
        now: Date = Date(),
        days: Int = 7
    ) -> [String: Int] {
        guard days > 0,
              let content = readFile(filePath),
              !content.isEmpty
        else { return [:] }

        let formatter = ISO8601DateFormatter()
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        var counts: [String: Int] = [:]

        content.enumerateLines { line, _ in
            guard let entry = HistoryEntry.fromJSON(line),
                  let ts = formatter.date(from: entry.ts),
                  ts >= cutoff,
                  ts <= now,
                  let token = Self.slashUsageToken(from: entry.text)
            else { return }
            counts[token, default: 0] += 1
        }

        return counts
    }

    /// Append a new entry to the history file.
    func append(text: String, filePath: String) {
        let entry = HistoryEntry(text: text, ts: ISO8601DateFormatter().string(from: Date()))
        guard let json = entry.toJSON() else { return }
        appendFile(filePath, json)
    }

    /// Compact the history file: load all entries, deduplicate, trim, and rewrite.
    /// Call this periodically (e.g., on startup) to prevent unbounded file growth.
    func compact(filePath: String) {
        guard let content = readFile(filePath), !content.isEmpty else { return }

        var entries: [HistoryEntry] = []
        content.enumerateLines { line, _ in
            if let entry = HistoryEntry.fromJSON(line) {
                entries.append(entry)
            }
        }

        // Only compact if file has more entries than our max
        guard entries.count > Self.maxEntries else { return }

        // Dedup + trim
        var seen = Set<String>()
        var deduped: [HistoryEntry] = []
        for entry in entries.reversed() {
            let key = entry.text.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(entry)
            }
        }
        deduped.reverse()

        if deduped.count > Self.maxEntries {
            deduped = Array(deduped.suffix(Self.maxEntries))
        }

        // Rewrite file
        let lines = deduped.compactMap { $0.toJSON() }
        writeFile(filePath, lines.joined(separator: "\n") + "\n")
    }

    // MARK: - Entry Model

    private struct HistoryEntry: Sendable {
        let text: String
        let ts: String

        static func fromJSON(_ line: String) -> HistoryEntry? {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let text = obj["text"]
            else { return nil }
            return HistoryEntry(text: text, ts: obj["ts"] ?? "")
        }

        func toJSON() -> String? {
            let obj: [String: String] = ["text": text, "ts": ts]
            guard let data = try? JSONSerialization.data(
                withJSONObject: obj,
                options: .sortedKeys
            ) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    private static func slashUsageToken(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ", maxSplits: 1).first else {
            return nil
        }
        let token = String(first).lowercased()
        guard token.hasPrefix("/") else { return nil }
        return SlashCommand.parse(token)?.rawValue ?? token
    }
}
