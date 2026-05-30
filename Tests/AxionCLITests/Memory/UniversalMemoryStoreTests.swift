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
}
