import Testing
import Foundation

@testable import AxionCLI

@Suite("UniversalMemoryStore")
struct UniversalMemoryStoreTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Init

    @Test("init creates MEMORY.md and USER.md if missing")
    func initCreatesFiles() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        let memoryContent = await store.read(target: .memory)
        let userContent = await store.read(target: .user)

        #expect(memoryContent == "")
        #expect(userContent == "")

        // Verify files exist on disk
        let memoryURL = dir.appendingPathComponent("MEMORY.md")
        let userURL = dir.appendingPathComponent("USER.md")
        #expect(FileManager.default.fileExists(atPath: memoryURL.path))
        #expect(FileManager.default.fileExists(atPath: userURL.path))
    }

    @Test("init creates directory if missing")
    func initCreatesDir() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        let content = await store.read(target: .memory)
        #expect(content == "")
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - Read / Write

    @Test("write and read round-trip")
    func writeRead() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        await store.write(target: .memory, content: "hello world")
        let result = await store.read(target: .memory)
        #expect(result == "hello world")
    }

    @Test("read returns empty string when file missing")
    func readMissingFile() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        // Delete the file manually after init
        let store = UniversalMemoryStore(memoryDir: dir.path)
        let url = dir.appendingPathComponent("MEMORY.md")
        try? FileManager.default.removeItem(at: url)

        let content = await store.read(target: .memory)
        #expect(content == "")
    }

    // MARK: - Add

    @Test("add appends § delimited entry")
    func addEntry() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        let ok = await store.add(target: .memory, content: "project uses Swift 6.1")
        #expect(ok == true)

        let content = await store.read(target: .memory)
        #expect(content.contains("§"))
        #expect(content.contains("project uses Swift 6.1"))
    }

    @Test("add returns false when exceeding char limit")
    func addExceedsLimit() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 50)
        _ = await store.add(target: .memory, content: "short entry")
        let ok = await store.add(target: .memory, content: String(repeating: "x", count: 60))
        #expect(ok == false)
    }

    @Test("add respects separate user char limit")
    func addUserLimit() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000, maxUserChars: 30)
        let ok = await store.add(target: .user, content: String(repeating: "y", count: 40))
        #expect(ok == false)
    }

    // MARK: - Remove

    @Test("remove entry by keyword")
    func removeEntry() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        _ = await store.add(target: .memory, content: "alpha")
        _ = await store.add(target: .memory, content: "beta")
        _ = await store.add(target: .memory, content: "gamma")

        let removed = await store.remove(target: .memory, keyword: "beta")
        #expect(removed == true)

        let content = await store.read(target: .memory)
        #expect(content.contains("alpha"))
        #expect(!content.contains("beta"))
        #expect(content.contains("gamma"))
    }

    @Test("remove returns false when keyword not found")
    func removeNotFound() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        _ = await store.add(target: .memory, content: "alpha")

        let removed = await store.remove(target: .memory, keyword: "nonexistent")
        #expect(removed == false)
    }

    // MARK: - Replace

    @Test("replace entry by keyword")
    func replaceEntry() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        _ = await store.add(target: .memory, content: "old value")

        let replaced = await store.replace(target: .memory, keyword: "old", newContent: "new value")
        #expect(replaced == true)

        let content = await store.read(target: .memory)
        #expect(!content.contains("old value"))
        #expect(content.contains("new value"))
    }

    @Test("replace returns false when keyword not found")
    func replaceNotFound() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        _ = await store.add(target: .memory, content: "alpha")

        let replaced = await store.replace(target: .memory, keyword: "nonexistent", newContent: "beta")
        #expect(replaced == false)
    }

    @Test("replace returns false when result exceeds char limit")
    func replaceExceedsLimit() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 50)
        _ = await store.add(target: .memory, content: "short")

        let replaced = await store.replace(target: .memory, keyword: "short", newContent: String(repeating: "x", count: 80))
        #expect(replaced == false)

        // Verify original content is preserved
        let content = await store.read(target: .memory)
        #expect(content.contains("short"))
    }

    // MARK: - Char Count

    @Test("charCount returns correct count")
    func charCount() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        await store.write(target: .memory, content: "12345")
        let count = await store.charCount(target: .memory)
        #expect(count == 5)
    }

    @Test("charCount returns 0 for empty file")
    func charCountEmpty() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        let count = await store.charCount(target: .memory)
        #expect(count == 0)
    }

    // MARK: - Entry Count

    @Test("entryCount returns 0 for empty file")
    func entryCountEmpty() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        let count = await store.entryCount(target: .memory)
        #expect(count == 0)
    }

    @Test("entryCount returns correct count for populated file")
    func entryCountPopulated() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        _ = await store.add(target: .memory, content: "first entry")
        _ = await store.add(target: .memory, content: "second entry")
        _ = await store.add(target: .memory, content: "third entry")

        let count = await store.entryCount(target: .memory)
        #expect(count == 3)
    }

    @Test("entryCount counts entries independently for each target")
    func entryCountPerTarget() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000, maxUserChars: 1000)
        _ = await store.add(target: .memory, content: "mem1")
        _ = await store.add(target: .memory, content: "mem2")
        _ = await store.add(target: .user, content: "user1")

        let memCount = await store.entryCount(target: .memory)
        let userCount = await store.entryCount(target: .user)
        #expect(memCount == 2)
        #expect(userCount == 1)
    }

    // MARK: - Last Modified Date

    @Test("lastModifiedDate returns nil for missing file")
    func lastModifiedDateMissing() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        // Delete the file after init
        let url = dir.appendingPathComponent("MEMORY.md")
        try? FileManager.default.removeItem(at: url)

        let date = await store.lastModifiedDate(target: .memory)
        #expect(date == nil)
    }

    @Test("lastModifiedDate returns date for existing file")
    func lastModifiedDateExists() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        await store.write(target: .memory, content: "some content")

        let date = await store.lastModifiedDate(target: .memory)
        #expect(date != nil, "Should return a modification date for an existing file")
    }

    // MARK: - Parse Entries (public)

    @Test("parseEntries splits § delimited content")
    func parseEntriesPublic() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        let content = "§\nalpha\n§\n§\nbeta\n§\n"
        let entries = await store.parseEntries(from: content)
        #expect(entries == ["alpha", "beta"])
    }

    // MARK: - Default limits

    @Test("default char limits are 4000 and 2000")
    func defaultLimits() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path)
        let memLimit = await store.maxMemoryChars
        let userLimit = await store.maxUserChars
        #expect(memLimit == 4000)
        #expect(userLimit == 2000)
    }

    // MARK: - Summary

    @Test("summary returns count and date in one call")
    func summaryReturnsCountAndDate() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(memoryDir: dir.path, maxMemoryChars: 1000)
        _ = await store.add(target: .memory, content: "first")
        _ = await store.add(target: .memory, content: "second")

        let info = await store.summary(target: .memory)
        #expect(info.count == 2, "Summary should report 2 entries")
        #expect(info.lastModified != nil, "Summary should return a modification date")
    }

    @Test("summary returns 0 count and nil date for missing file")
    func summaryMissingFile() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let store = UniversalMemoryStore(readOnlyMemoryDir: "/tmp/axion-test-nonexistent-\(UUID().uuidString)")
        let info = await store.summary(target: .memory)
        #expect(info.count == 0, "Summary should report 0 entries for missing file")
        #expect(info.lastModified == nil, "Summary should return nil date for missing file")
    }

    // MARK: - Read-only init

    @Test("readOnlyMemoryDir init does not create files")
    func readOnlyInitNoSideEffects() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let nestedDir = dir.appendingPathComponent("sub-\(UUID().uuidString)")
        let store = UniversalMemoryStore(readOnlyMemoryDir: nestedDir.path)
        let content = await store.read(target: .memory)
        #expect(content == "", "Read should return empty for missing directory")
        #expect(!FileManager.default.fileExists(atPath: nestedDir.path),
            "Read-only init should NOT create the directory")
    }
}
