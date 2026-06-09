import Testing
import Foundation
@testable import AxionCLI

@Suite("GatewaySessionStore")
struct GatewaySessionStoreTests {

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory().appending("GatewaySessionStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test("recordTurn increments counters for new chatId")
    func recordTurnNew() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")
        let store = GatewaySessionStore(filePath: path)

        await store.recordTurn(chatId: 123, sessionId: "sess-1")
        let state = await store.state(for: 123)

        #expect(state != nil)
        #expect(state?.userTurnCount == 1)
        #expect(state?.turnsSinceMemory == 1)
        #expect(state?.sessionIds == ["sess-1"])
    }

    @Test("recordTurn accumulates across multiple calls")
    func recordTurnAccumulates() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")
        let store = GatewaySessionStore(filePath: path)

        for i in 0..<4 {
            await store.recordTurn(chatId: 100, sessionId: "sess-\(i)")
        }
        let state = await store.state(for: 100)

        #expect(state?.userTurnCount == 4)
        #expect(state?.turnsSinceMemory == 4)
        #expect(state?.sessionIds.count == 4)
    }

    @Test("resetMemoryCounter sets turnsSinceMemory to 0")
    func resetMemoryCounter() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")
        let store = GatewaySessionStore(filePath: path)

        await store.recordTurn(chatId: 200, sessionId: "s1")
        await store.recordTurn(chatId: 200, sessionId: "s2")
        await store.resetMemoryCounter(chatId: 200)

        let state = await store.state(for: 200)
        #expect(state?.userTurnCount == 2)
        #expect(state?.turnsSinceMemory == 0)
    }

    @Test("clearSession removes state for chatId")
    func clearSession() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")
        let store = GatewaySessionStore(filePath: path)

        await store.recordTurn(chatId: 300, sessionId: "s1")
        #expect(await store.state(for: 300) != nil)

        await store.clearSession(chatId: 300)
        #expect(await store.state(for: 300) == nil)
    }

    @Test("persistence round-trip saves and loads state")
    func persistenceRoundTrip() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")

        // Write state
        let store1 = GatewaySessionStore(filePath: path)
        await store1.recordTurn(chatId: 400, sessionId: "sess-a")
        await store1.recordTurn(chatId: 400, sessionId: "sess-b")
        await store1.resetMemoryCounter(chatId: 400)
        await store1.recordTurn(chatId: 500, sessionId: "sess-c")

        // Load into a new instance
        let store2 = GatewaySessionStore(filePath: path)
        try await store2.load()

        let state400 = await store2.state(for: 400)
        #expect(state400?.userTurnCount == 2)
        #expect(state400?.turnsSinceMemory == 0) // resetMemoryCounter set to 0

        let state500 = await store2.state(for: 500)
        #expect(state500?.userTurnCount == 1)
        #expect(state500?.turnsSinceMemory == 1)
    }

    @Test("load with missing file starts empty")
    func loadMissingFile() async throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("nonexistent.json")

        let store = GatewaySessionStore(filePath: path)
        try await store.load()

        #expect(await store.state(for: 999) == nil)
    }

    @Test("independent turn counting for multiple chatIds")
    func independentChatIds() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")
        let store = GatewaySessionStore(filePath: path)

        await store.recordTurn(chatId: 800, sessionId: "s1")
        await store.recordTurn(chatId: 800, sessionId: "s2")
        await store.recordTurn(chatId: 900, sessionId: "s3")

        let state800 = await store.state(for: 800)
        let state900 = await store.state(for: 900)

        #expect(state800?.userTurnCount == 2)
        #expect(state900?.userTurnCount == 1)

        // Clearing one doesn't affect the other
        await store.clearSession(chatId: 800)
        #expect(await store.state(for: 800) == nil)
        #expect(await store.state(for: 900)?.userTurnCount == 1)
    }

    @Test("recordSessionId appends after execution")
    func recordSessionIdAfterExecution() async {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let path = (dir as NSString).appendingPathComponent("sessions.json")
        let store = GatewaySessionStore(filePath: path)

        // First turn — sessionId not yet known
        await store.recordTurn(chatId: 1000, sessionId: "")
        // After execution, sessionId becomes known
        await store.recordSessionId(chatId: 1000, sessionId: "actual-sess-1")

        let state = await store.state(for: 1000)
        #expect(state?.sessionIds == ["actual-sess-1"])
        #expect(state?.userTurnCount == 1)
    }
}
