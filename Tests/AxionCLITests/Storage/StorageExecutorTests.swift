import Testing
import Foundation

import AxionCore
@testable import AxionCLI

@Suite("Storage Executor")
struct StorageExecutorTests {

    private func makeTempDir(_ label: String) throws -> URL {
        let scratchRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("StorageExecScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let dir = scratchRoot
            .appendingPathComponent("axion-exec-\(label)-\(UUID().uuidString)", isDirectory: true)
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

    private func makeExecutor(root: URL, ops: URL) -> (StorageExecutor, StorageManifestStore) {
        let store = StorageManifestStore(storageOpsDir: ops.path, homeDirectory: root.path)
        return (StorageExecutor(manifestStore: store), store)
    }

    private func request(
        op: String,
        root: URL,
        items: [ExecutionItem],
        surface: StorageSurface = .run
    ) -> ExecuteRequest {
        ExecuteRequest(
            operationId: op,
            surface: surface,
            scanRoots: [root],
            items: items,
            homeDirectory: root.path,
            storageOpsDir: ""  // unused by executor (store holds dir); placeholder
        )
    }

    // MARK: - Happy paths

    @Test("execute moves a file, re-reads size from disk, and persists manifest")
    func executeMovesFileAndPersistsManifest() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let source = root.appendingPathComponent("invoice.pdf")
        let target = root.appendingPathComponent("Documents/invoice.pdf")
        try writeFile(source, bytes: 50)

        let (executor, store) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-move-1",
            root: root,
            items: [ExecutionItem(action: .move, source: source.path, target: target.path, sizeBytes: 999)]
        ))

        // Side effect: file relocated.
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: target.path))

        // Size re-read from disk (ignores the 999 hint).
        #expect(result.succeeded == 1)
        #expect(result.failed == 0)
        let item = try #require(result.manifest.items.first)
        #expect(item.outcome == .succeeded)
        #expect(item.action == .move)
        #expect(item.sizeBytes == 50)
        #expect(item.targetPath == target.path)
        #expect(result.manifest.status == .completed)
        #expect(result.manifest.completedAt != nil)

        // Persisted to disk (draft-first + completion overwrite).
        let loaded = try #require(store.load(operationId: "op-move-1"))
        #expect(loaded.status == .completed)
        #expect(loaded.items.first?.sourcePath == source.path)
        #expect(loaded.approvedByUser?.contains("approved via run") == true)
    }

    @Test("execute creates a directory idempotently")
    func executeCreateDirectorySucceedsAndIsIdempotent() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let dir = root.appendingPathComponent("Archive/2026")
        let (executor, _) = makeExecutor(root: root, ops: ops)

        let r1 = await executor.execute(request(op: "op-mkdir-1", root: root, items: [ExecutionItem(action: .createDirectory, source: dir.path)]))
        #expect(r1.succeeded == 1)
        #expect(r1.manifest.items.first?.outcome == .succeeded)
        #expect(FileManager.default.fileExists(atPath: dir.path))

        // Second run: idempotent — still succeeded (mkdir -p semantics).
        let r2 = await executor.execute(request(op: "op-mkdir-2", root: root, items: [ExecutionItem(action: .createDirectory, source: dir.path)]))
        #expect(r2.manifest.items.first?.outcome == .succeeded)
    }

    @Test("execute treats scan_only as skipped (no side effect)")
    func executeScanOnlyIsSkipped() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let file = root.appendingPathComponent("note.txt")
        try writeFile(file, bytes: 10)
        let (executor, _) = makeExecutor(root: root, ops: ops)

        let result = await executor.execute(request(op: "op-scan-1", root: root, items: [ExecutionItem(action: .scanOnly, source: file.path)]))
        #expect(result.skipped == 1)
        #expect(result.manifest.items.first?.outcome == .skipped)
        // No side effect: file still present.
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Re-validation (defense in depth, AC #5)

    @Test("execute rejects uninstall_app and records it in errors")
    func executeRejectsUninstallAppAndRecordsError() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-reject-app",
            root: root,
            items: [ExecutionItem(action: .uninstallApp, source: root.appendingPathComponent("Demo.app").path)]
        ))

        // Dropped to errors (audited), never executed → no manifest item.
        #expect(result.manifest.items.isEmpty)
        #expect(result.manifest.errors.contains { $0.contains("action_not_allowed") })
        // Any dropped item (or execution failure) → partiallyFailed, NOT completed:
        // a fully-rejected plan must not masquerade as a clean success to status-gated callers.
        #expect(result.manifest.status == .partiallyFailed)
    }

    @Test("execute rejects sources outside scan_roots")
    func executeRejectsSourceOutsideScanRoots() async throws {
        let root = try makeTempDir("root")
        let outside = try makeTempDir("outside")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(outside); cleanup(ops) }

        let outsideFile = outside.appendingPathComponent("stray.txt")
        try writeFile(outsideFile, bytes: 5)

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-reject-outside",
            root: root,
            items: [ExecutionItem(action: .move, source: outsideFile.path, target: root.appendingPathComponent("x.txt").path)]
        ))

        #expect(result.manifest.items.isEmpty)
        #expect(result.manifest.errors.contains { $0.contains("outside_scan_roots") })
        // Source untouched.
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("execute rejects excluded .git paths")
    func executeRejectsExcludedGitPath() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let gitFile = root.appendingPathComponent(".git/config")
        try writeFile(gitFile, bytes: 3)

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-reject-git",
            root: root,
            items: [ExecutionItem(action: .move, source: gitFile.path, target: root.appendingPathComponent("config").path)]
        ))

        #expect(result.manifest.errors.contains { $0.contains("git_directory") || $0.contains("excluded") })
        // Source untouched.
        #expect(FileManager.default.fileExists(atPath: gitFile.path))
    }

    @Test("execute rejects missing sources")
    func executeRejectsMissingSource() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-reject-missing",
            root: root,
            items: [ExecutionItem(action: .move, source: root.appendingPathComponent("ghost.txt").path, target: root.appendingPathComponent("out.txt").path)]
        ))

        #expect(result.manifest.errors.contains { $0.contains("source_missing") })
    }

    @Test("execute rejects symlink targets (not followed)")
    func executeRejectsSymlinkTarget() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let real = root.appendingPathComponent("real.txt")
        let link = root.appendingPathComponent("link.txt")
        try writeFile(real, bytes: 4)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-reject-symlink",
            root: root,
            items: [ExecutionItem(action: .move, source: link.path, target: root.appendingPathComponent("out.txt").path)]
        ))

        #expect(result.manifest.errors.contains { $0.contains("symlink_target_not_followed") })
        // Neither link nor real moved.
        #expect(FileManager.default.fileExists(atPath: link.path))
        #expect(FileManager.default.fileExists(atPath: real.path))
    }

    // MARK: - No-overwrite (AC #7) + independent per-item failure (AC #6)

    @Test("execute does not overwrite an existing target")
    func executeMoveDoesNotOverwriteExistingTarget() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let source = root.appendingPathComponent("a.txt")
        let target = root.appendingPathComponent("b.txt")
        try writeFile(source, bytes: 10)
        try writeFile(target, bytes: 99)  // pre-existing target content

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-nooverwrite",
            root: root,
            items: [ExecutionItem(action: .move, source: source.path, target: target.path)]
        ))

        let item = try #require(result.manifest.items.first)
        #expect(item.outcome == .failed)
        #expect(item.reason == "target_exists")
        // Source untouched, target content preserved.
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect((try? Data(contentsOf: target).count) == 99)
    }

    @Test("execute continues after a per-item failure (independent, status partiallyFailed)")
    func executeContinuesAfterPerItemFailure() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let good = root.appendingPathComponent("good.txt")
        let goodTarget = root.appendingPathComponent("out/good.txt")
        let badSource = root.appendingPathComponent("bad.txt")
        let badTarget = root.appendingPathComponent("existing.txt")  // pre-existing → target_exists
        try writeFile(good, bytes: 8)
        try writeFile(badSource, bytes: 8)
        try writeFile(badTarget, bytes: 1)

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(
            op: "op-mixed",
            root: root,
            items: [
                ExecutionItem(action: .move, source: good.path, target: goodTarget.path),
                ExecutionItem(action: .move, source: badSource.path, target: badTarget.path),
            ]
        ))

        // Good item still succeeded despite the sibling failure.
        #expect(result.succeeded == 1)
        #expect(result.failed == 1)
        #expect(FileManager.default.fileExists(atPath: goodTarget.path))
        // Batch status reflects the failure.
        #expect(result.manifest.status == .partiallyFailed)
        let outcomes = result.manifest.items.map(\.outcome)
        #expect(outcomes.contains(.succeeded))
        #expect(outcomes.contains(.failed))
    }

    // MARK: - trash (recoverable; small disposable file → system Trash)

    @Test("execute trashes a file (recoverable, records trashResultPath)")
    func executeTrashesFile() async throws {
        let root = try makeTempDir("root")
        let ops = try makeTempDir("ops")
        defer { cleanup(root); cleanup(ops) }

        let file = root.appendingPathComponent("disposable-\(UUID().uuidString).tmp")
        try writeFile(file, bytes: 6)

        let (executor, _) = makeExecutor(root: root, ops: ops)
        let result = await executor.execute(request(op: "op-trash-1", root: root, items: [ExecutionItem(action: .trash, source: file.path)]))

        #expect(result.succeeded == 1)
        let item = try #require(result.manifest.items.first)
        #expect(item.outcome == .succeeded)
        #expect(item.action == .trash)
        #expect(item.trashResultPath != nil)  // undo depends on this
        // Source removed (moved to system Trash).
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
