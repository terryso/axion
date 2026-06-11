import Testing
import Foundation

import AxionCore
@testable import AxionCLI

@Suite("Storage Manifest Store")
struct StorageManifestStoreTests {

    private func makeTempDir(_ label: String) throws -> URL {
        let scratchRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("StorageStoreScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let dir = scratchRoot
            .appendingPathComponent("axion-store-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(ops: URL, home: String) -> StorageManifestStore {
        StorageManifestStore(storageOpsDir: ops.path, homeDirectory: home)
    }

    private func sampleManifest(op: String, status: StorageOpStatus, undoneAt: String? = nil) -> StorageManifest {
        var m = StorageManifest(
            operationId: op,
            createdAt: "2026-06-11T00:00:00Z",
            surface: .run,
            items: [StorageManifestItem(action: .move, sourcePath: "/a", targetPath: "/b", outcome: .succeeded)],
            status: status,
            errors: []
        )
        m.undoneAt = undoneAt
        return m
    }

    @Test("save then load round-trips a manifest")
    func saveThenLoadRoundTrips() throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let store = makeStore(ops: ops, home: ops.path)

        let manifest = sampleManifest(op: "op-rt-1", status: .completed)
        try store.save(manifest)

        let loaded = try #require(store.load(operationId: "op-rt-1"))
        #expect(loaded == manifest)
        #expect(loaded.items.first?.action == .move)
    }

    @Test("load returns nil for unknown operationId")
    func loadMissingReturnsNil() throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let store = makeStore(ops: ops, home: ops.path)

        #expect(store.load(operationId: "never-saved") == nil)
    }

    @Test("listRecent orders by modification date descending")
    func listRecentOrdersByMtimeDescending() throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let store = makeStore(ops: ops, home: ops.path)

        // Save three manifests, then force distinct mtimes (deterministic, sub-second-agnostic).
        try store.save(sampleManifest(op: "old", status: .completed))
        try store.save(sampleManifest(op: "mid", status: .completed))
        try store.save(sampleManifest(op: "new", status: .completed))

        let tOld = Date(timeIntervalSince1970: 1_000)
        let tMid = Date(timeIntervalSince1970: 2_000)
        let tNew = Date(timeIntervalSince1970: 3_000)
        try FileManager.default.setAttributes([.modificationDate: tOld], ofItemAtPath: store.resolveManifestPath("old"))
        try FileManager.default.setAttributes([.modificationDate: tMid], ofItemAtPath: store.resolveManifestPath("mid"))
        try FileManager.default.setAttributes([.modificationDate: tNew], ofItemAtPath: store.resolveManifestPath("new"))

        let recent = store.listRecent()
        #expect(recent.map(\.operationId) == ["new", "mid", "old"])
    }

    @Test("mostRecentUndoable skips planned and already-undone manifests")
    func mostRecentUndoableFiltersCorrectly() throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let store = makeStore(ops: ops, home: ops.path)

        // planned (not terminal) → skipped
        try store.save(sampleManifest(op: "planned", status: .planned))
        // completed but already undone → skipped
        try store.save(sampleManifest(op: "done-undone", status: .completed, undoneAt: "2026-06-11T01:00:00Z"))
        // completed, not undone → candidate (most recent)
        try store.save(sampleManifest(op: "done-fresh", status: .completed))

        // Force mtime ordering: done-fresh newest.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: store.resolveManifestPath("planned"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: store.resolveManifestPath("done-undone"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 3_000)], ofItemAtPath: store.resolveManifestPath("done-fresh"))

        let undoable = try #require(store.mostRecentUndoable())
        #expect(undoable.operationId == "done-fresh")
        #expect(undoable.undoneAt == nil)
    }

    @Test("mostRecentUndoable also accepts partiallyFailed terminal status")
    func mostRecentUndoableAcceptsPartiallyFailed() throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let store = makeStore(ops: ops, home: ops.path)

        try store.save(sampleManifest(op: "pf", status: .partiallyFailed))
        let undoable = try #require(store.mostRecentUndoable())
        #expect(undoable.operationId == "pf")
        #expect(undoable.status == .partiallyFailed)
    }

    @Test("mostRecentUndoable returns nil when nothing qualifies")
    func mostRecentUndoableReturnsNilWhenEmpty() throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let store = makeStore(ops: ops, home: ops.path)
        #expect(store.mostRecentUndoable() == nil)
    }

    @Test("trySave returns false when the ops dir cannot be created")
    func trySaveReturnsFalseForBlockedDir() throws {
        // Create a plain file at the target dir path so createDirectory fails.
        let blockerParent = try makeTempDir("block")
        let blocker = blockerParent.appendingPathComponent("is-a-file")
        try Data().write(to: blocker)
        defer { cleanup(blockerParent) }

        let store = StorageManifestStore(storageOpsDir: blocker.path, homeDirectory: blockerParent.path)
        let ok = store.trySave(sampleManifest(op: "blocked", status: .planned))
        #expect(ok == false)
    }
}
