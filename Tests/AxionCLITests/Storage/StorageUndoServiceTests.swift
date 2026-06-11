import Testing
import Foundation

import AxionCore
@testable import AxionCLI

@Suite("Storage Undo Service")
struct StorageUndoServiceTests {

    private func makeTempDir(_ label: String) throws -> URL {
        let scratchRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("StorageUndoScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let dir = scratchRoot
            .appendingPathComponent("axion-undo-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    private func makeService(ops: URL) -> (StorageUndoService, StorageManifestStore) {
        let store = StorageManifestStore(storageOpsDir: ops.path, homeDirectory: ops.path)
        return (StorageUndoService(manifestStore: store), store)
    }

    private func request(op: String?, ops: URL) -> UndoRequest {
        UndoRequest(operationId: op, storageOpsDir: ops.path, homeDirectory: ops.path)
    }

    private func seedManifest(_ store: StorageManifestStore, items: [StorageManifestItem], op: String) throws -> StorageManifest {
        let m = StorageManifest(
            operationId: op,
            createdAt: "2026-06-11T00:00:00Z",
            surface: .run,
            items: items,
            status: .completed,
            errors: []
        )
        try store.save(m)
        return m
    }

    // MARK: - move undo

    @Test("undo moves a file back to its original source")
    func undoMoveRestoresFileToSource() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let source = work.appendingPathComponent("orig.txt")
        let target = work.appendingPathComponent("moved/orig.txt")
        try writeFile(target, bytes: 12)  // file currently at target; source absent

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .move, sourcePath: source.path, targetPath: target.path, outcome: .succeeded),
        ], op: "op-undo-move-1")

        let result = try #require(await service.undo(request(op: "op-undo-move-1", ops: ops)))
        #expect(result.restored == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: target.path))

        // Written back to manifest.
        let loaded = try #require(store.load(operationId: "op-undo-move-1"))
        #expect(loaded.undoneAt != nil)
        #expect(loaded.undoResults?.first?.outcome == .restored)
    }

    @Test("undo move does not overwrite when source already exists")
    func undoMoveSourceAlreadyExists() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let source = work.appendingPathComponent("orig.txt")
        let target = work.appendingPathComponent("moved/orig.txt")
        try writeFile(source, bytes: 5)
        try writeFile(target, bytes: 9)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .move, sourcePath: source.path, targetPath: target.path, outcome: .succeeded),
        ], op: "op-undo-move-2")

        let result = try #require(await service.undo(request(op: "op-undo-move-2", ops: ops)))
        #expect(result.notRestored == 1)
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.outcome == .notRestored)
        #expect(r.reason == "source_already_exists")
        // Both files preserved.
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("undo move reports target_missing when target is gone")
    func undoMoveTargetMissing() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .move, sourcePath: work.appendingPathComponent("gone-src.txt").path, targetPath: work.appendingPathComponent("gone-tgt.txt").path, outcome: .succeeded),
        ], op: "op-undo-move-3")

        let result = try #require(await service.undo(request(op: "op-undo-move-3", ops: ops)))
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.outcome == .notRestored)
        #expect(r.reason == "target_missing")
    }

    // MARK: - trash undo

    @Test("undo trash restores from trashResultPath")
    func undoTrashRestoresFromTrashResultPath() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let source = work.appendingPathComponent("orig.bin")
        let trashLoc = work.appendingPathComponent("trashloc/orig.bin")
        try writeFile(trashLoc, bytes: 7)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .trash, sourcePath: source.path, trashResultPath: trashLoc.path, outcome: .succeeded),
        ], op: "op-undo-trash-1")

        let result = try #require(await service.undo(request(op: "op-undo-trash-1", ops: ops)))
        #expect(result.restored == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: trashLoc.path))
    }

    @Test("undo trash reports item_no_longer_in_trash when trash path is gone")
    func undoTrashItemNoLongerInTrash() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .trash, sourcePath: work.appendingPathComponent("orig.bin").path, trashResultPath: work.appendingPathComponent("emptied/orig.bin").path, outcome: .succeeded),
        ], op: "op-undo-trash-2")

        let result = try #require(await service.undo(request(op: "op-undo-trash-2", ops: ops)))
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.outcome == .notRestored)
        #expect(r.reason == "item_no_longer_in_trash")
    }

    // MARK: - uninstallApp undo (AC #10, 39.3)

    @Test("undo uninstallApp restores bundle from trashResultPath")
    func undoUninstallAppRestoresFromTrashResultPath() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let source = work.appendingPathComponent("Apps/Foo.app")  // 原 bundle 路径（已不在）
        let trashLoc = work.appendingPathComponent("trash/Foo.app")  // 废纸篓落位
        // moveItem 要求目标父目录存在 → 预建 Apps 父目录（bundle 原父目录）。
        try FileManager.default.createDirectory(at: work.appendingPathComponent("Apps"), withIntermediateDirectories: true)
        // 伪造废纸篓中的 bundle
        try FileManager.default.createDirectory(at: trashLoc.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 4).write(to: trashLoc.appendingPathComponent("Contents/Info.plist"))

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .uninstallApp, sourcePath: source.path, trashResultPath: trashLoc.path, outcome: .succeeded),
        ], op: "op-undo-app-1")

        let result = try #require(await service.undo(request(op: "op-undo-app-1", ops: ops)))
        #expect(result.restored == 1)
        // 恢复回原 bundle 路径；废纸篓落位移走
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: trashLoc.path))
        // action 正确标记为 uninstallApp（非 trash）
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.action == .uninstallApp)
        #expect(r.outcome == .restored)
    }

    @Test("undo uninstallApp reports item_no_longer_in_trash when trash path gone")
    func undoUninstallAppItemNoLongerInTrash() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .uninstallApp, sourcePath: work.appendingPathComponent("Apps/Foo.app").path, trashResultPath: work.appendingPathComponent("emptied/Foo.app").path, outcome: .succeeded),
        ], op: "op-undo-app-2")

        let result = try #require(await service.undo(request(op: "op-undo-app-2", ops: ops)))
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.action == .uninstallApp)
        #expect(r.outcome == .notRestored)
        #expect(r.reason == "item_no_longer_in_trash")
    }

    @Test("undo uninstallApp does not overwrite when source already exists")
    func undoUninstallAppSourceAlreadyExists() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let source = work.appendingPathComponent("Apps/Foo.app")
        let trashLoc = work.appendingPathComponent("trash/Foo.app")
        // source 已存在（如用户已重装）→ 不覆盖
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashLoc, withIntermediateDirectories: true)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .uninstallApp, sourcePath: source.path, trashResultPath: trashLoc.path, outcome: .succeeded),
        ], op: "op-undo-app-3")

        let result = try #require(await service.undo(request(op: "op-undo-app-3", ops: ops)))
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.outcome == .notRestored)
        #expect(r.reason == "source_already_exists")
        // 两处都保留
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: trashLoc.path))
    }

    @Test("uninstallApp undo coexists with other item actions in same manifest")
    func undoUninstallAppAlongsideOthers() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let bundleSource = work.appendingPathComponent("Apps/Foo.app")
        let bundleTrash = work.appendingPathComponent("trash/Foo.app")
        try FileManager.default.createDirectory(at: bundleTrash, withIntermediateDirectories: true)
        let cacheSource = work.appendingPathComponent("Caches/com.example.foo")
        let cacheTrash = work.appendingPathComponent("trash/com.example.foo")
        try FileManager.default.createDirectory(at: cacheTrash, withIntermediateDirectories: true)
        // moveItem 要求目标父目录存在 → 预建 Apps / Caches 父目录。
        try FileManager.default.createDirectory(at: work.appendingPathComponent("Apps"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("Caches"), withIntermediateDirectories: true)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .uninstallApp, sourcePath: bundleSource.path, trashResultPath: bundleTrash.path, outcome: .succeeded),
            StorageManifestItem(action: .trash, sourcePath: cacheSource.path, trashResultPath: cacheTrash.path, outcome: .succeeded),
        ], op: "op-undo-app-4")

        let result = try #require(await service.undo(request(op: "op-undo-app-4", ops: ops)))
        #expect(result.restored == 2)
        #expect(FileManager.default.fileExists(atPath: bundleSource.path))
        #expect(FileManager.default.fileExists(atPath: cacheSource.path))
    }

    // MARK: - createDirectory undo

    @Test("undo createDirectory removes an empty directory")
    func undoCreateDirectoryRemovesEmptyDir() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let dir = work.appendingPathComponent("NewFolder")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .createDirectory, sourcePath: dir.path, outcome: .succeeded),
        ], op: "op-undo-mkdir-1")

        let result = try #require(await service.undo(request(op: "op-undo-mkdir-1", ops: ops)))
        #expect(result.restored == 1)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("undo createDirectory refuses to remove a non-empty directory")
    func undoCreateDirectoryNotEmpty() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let dir = work.appendingPathComponent("NewFolder")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeFile(dir.appendingPathComponent("user-file.txt"), bytes: 3)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .createDirectory, sourcePath: dir.path, outcome: .succeeded),
        ], op: "op-undo-mkdir-2")

        let result = try #require(await service.undo(request(op: "op-undo-mkdir-2", ops: ops)))
        let r = try #require(result.manifest.undoResults?.first)
        #expect(r.outcome == .notRestored)
        #expect(r.reason == "directory_not_empty")
        // Directory + user content preserved (never permanently deleted).
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("user-file.txt").path))
    }

    // MARK: - skipped / not-found

    @Test("undo skips scan_only and originally-failed items")
    func undoSkipsScanOnlyAndFailedItems() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .scanOnly, sourcePath: work.appendingPathComponent("a.txt").path, outcome: .succeeded),
            StorageManifestItem(action: .move, sourcePath: work.appendingPathComponent("b.txt").path, targetPath: work.appendingPathComponent("c.txt").path, outcome: .failed, reason: "target_exists"),
        ], op: "op-undo-skip-1")

        let result = try #require(await service.undo(request(op: "op-undo-skip-1", ops: ops)))
        #expect(result.skipped == 2)
        #expect(result.restored == 0)
        let outcomes = result.manifest.undoResults?.map(\.outcome)
        #expect(outcomes == [.skipped, .skipped])
    }

    @Test("undo without operationId picks most recent undoable manifest")
    func undoWithoutOperationIdPicksMostRecent() async throws {
        let ops = try makeTempDir("ops")
        let work = try makeTempDir("work")
        defer { cleanup(ops); cleanup(work) }
        let (service, store) = makeService(ops: ops)

        let source = work.appendingPathComponent("orig.txt")
        let target = work.appendingPathComponent("moved/orig.txt")
        try writeFile(target, bytes: 4)
        _ = try seedManifest(store, items: [
            StorageManifestItem(action: .move, sourcePath: source.path, targetPath: target.path, outcome: .succeeded),
        ], op: "op-recent")

        let result = try #require(await service.undo(request(op: nil, ops: ops)))
        #expect(result.manifest.operationId == "op-recent")
        #expect(result.restored == 1)
    }

    @Test("undo returns nil when no manifest matches")
    func undoReturnsNilWhenNoManifest() async throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let (service, _) = makeService(ops: ops)

        let result = await service.undo(request(op: "does-not-exist", ops: ops))
        #expect(result == nil)
    }

    @Test("undo returns nil when nothing undoable exists")
    func undoReturnsNilWhenNothingUndoable() async throws {
        let ops = try makeTempDir("ops")
        defer { cleanup(ops) }
        let (service, _) = makeService(ops: ops)

        let result = await service.undo(request(op: nil, ops: ops))
        #expect(result == nil)
    }
}
