import Foundation

/// Target file for universal memory operations.
enum MemoryTarget: String, Sendable {
    case memory = "MEMORY.md"
    case user = "USER.md"
}

/// Actor managing the two universal memory files: MEMORY.md and USER.md.
///
/// All file I/O is serialized through actor isolation to prevent concurrent
/// write corruption. Errors are non-fatal — caught and logged to stderr,
/// never thrown to callers.
actor UniversalMemoryStore {

    private let memoryDir: URL
    private let fileManager = FileManager.default

    let maxMemoryChars: Int
    let maxUserChars: Int

    init(
        memoryDir: String,
        maxMemoryChars: Int = 4000,
        maxUserChars: Int = 2000
    ) {
        let expanded = (memoryDir as NSString).expandingTildeInPath
        self.memoryDir = URL(fileURLWithPath: expanded)
        self.maxMemoryChars = maxMemoryChars
        self.maxUserChars = maxUserChars
        Self.ensureFilesExistSync(in: self.memoryDir)
    }

    // MARK: - Read / Write

    func read(target: MemoryTarget) -> String {
        let url = fileURL(for: target)
        guard fileManager.fileExists(atPath: url.path) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func write(target: MemoryTarget, content: String) {
        let url = fileURL(for: target)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fputs("UniversalMemoryStore write error: \(error)\n", stderr)
        }
    }

    // MARK: - Entry Operations (§ delimited)

    /// Append a new entry. Returns `false` if adding would exceed the char limit.
    func add(target: MemoryTarget, content: String) -> Bool {
        let maxChars = maxChars(for: target)
        let current = read(target: target)
        let entry = "§\n\(content)\n§\n"
        if current.count + entry.count > maxChars {
            return false
        }
        write(target: target, content: current + entry)
        return true
    }

    /// Remove the first entry whose content contains `keyword` (case-insensitive).
    func remove(target: MemoryTarget, keyword: String) -> Bool {
        let content = read(target: target)
        var entries = parseEntries(from: content)
        let lowered = keyword.lowercased()
        guard let idx = entries.firstIndex(where: { $0.lowercased().contains(lowered) }) else {
            return false
        }
        entries.remove(at: idx)
        write(target: target, content: serializeEntries(entries))
        return true
    }

    /// Replace the first entry whose content contains `keyword` with `newContent`.
    /// Returns `false` if keyword not found or the result would exceed the char limit.
    func replace(target: MemoryTarget, keyword: String, newContent: String) -> Bool {
        let content = read(target: target)
        var entries = parseEntries(from: content)
        let lowered = keyword.lowercased()
        guard let idx = entries.firstIndex(where: { $0.lowercased().contains(lowered) }) else {
            return false
        }
        entries[idx] = newContent
        let serialized = serializeEntries(entries)
        if serialized.count > maxChars(for: target) {
            return false
        }
        write(target: target, content: serialized)
        return true
    }

    // MARK: - Char Count

    func charCount(target: MemoryTarget) -> Int {
        read(target: target).count
    }

    // MARK: - Private

    private func fileURL(for target: MemoryTarget) -> URL {
        memoryDir.appendingPathComponent(target.rawValue)
    }

    private func maxChars(for target: MemoryTarget) -> Int {
        switch target {
        case .memory: return maxMemoryChars
        case .user: return maxUserChars
        }
    }

    /// Synchronous file creation — called from init (non-isolated context).
    private static func ensureFilesExistSync(in memoryDir: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: memoryDir, withIntermediateDirectories: true)
            for target in [MemoryTarget.memory, .user] {
                let url = memoryDir.appendingPathComponent(target.rawValue)
                if !fm.fileExists(atPath: url.path) {
                    try "".write(to: url, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            fputs("UniversalMemoryStore init error: \(error)\n", stderr)
        }
    }

    /// Parse §-delimited entries from file content.
    private func parseEntries(from content: String) -> [String] {
        let parts = content.components(separatedBy: "§")
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Serialize entries back to §-delimited format.
    private func serializeEntries(_ entries: [String]) -> String {
        entries.map { "§\n\($0)\n§\n" }.joined()
    }
}
