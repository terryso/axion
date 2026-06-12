import Testing
import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

/// Story 39 E2E —— scan→propose→execute→undo 经 **Tool 层**完整闭环 + SEC 红线。
///
/// 用真实 `StorageScanService` / `StorageExecutor` / `StorageUndoService`（注入共享 manifestStore +
/// 隔离 trash），走 `StorageScanTool` → `ProposeStoragePlanTool` → `ExecuteStoragePlanTool` →
/// `UndoStorageOpTool` 的 `call(input:)`。各 tool 单元测试已分别覆盖，但未串联——本套件验证
/// 真实跨层集成：闭环、manifest 持久化、trash 可恢复（隔离、非永久删除）、逐项独立失败。
@Suite("Storage E2E — Tool Chain")
struct StorageToolChainE2ETests {

    private func scratch(_ label: String) throws -> URL {
        try StorageE2EFixture.makeScratch(label)
    }
    private func cleanup(_ url: URL) { StorageE2EFixture.cleanup(url) }
    private func writeFile(_ url: URL, bytes: Int = 8) throws {
        try StorageE2EFixture.writeFile(url, bytes: bytes)
    }
    private func toolPair(store: StorageManifestStore, trash: URL)
        -> (execute: ExecuteStoragePlanTool, undo: UndoStorageOpTool) {
        StorageE2EFixture.makeToolPair(store: store, trashPerformer: StorageE2EFixture.makeIsolatedTrash(trash))
    }
    private func context(_ cwd: String) -> ToolContext { StorageE2EFixture.makeContext(cwd: cwd) }
    private func decode(_ result: ToolResult) throws -> StorageManifest {
        try StorageE2EFixture.decodeManifest(result)
    }

    // MARK: - scan → propose → execute(move) → undo 闭环

    @Test("scan→propose→execute(move)→undo 全链路：文件移动后 undo 回原位")
    func e2e_scan_propose_execute_move_then_undo() async throws {
        let root = try scratch("chain-move")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let (executeTool, undoTool) = toolPair(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let file = scanRoot.appendingPathComponent("invoice.pdf")
        let target = scanRoot.appendingPathComponent("Documents/invoice.pdf")
        try writeFile(file, bytes: 16)

        // 1) scan（真实 ScanService）应发现该文件
        let scanTool = StorageScanTool(scanner: StorageScanService(homeDirectory: root.path))
        let scanResult = await scanTool.call(
            input: ["roots": [scanRoot.path], "min_size_mb": 0, "include_hidden": true] as [String: Any],
            context: context(scanRoot.path)
        )
        #expect(!scanResult.isError)
        let scanBody = try JSONSerialization.jsonObject(with: Data(scanResult.content.utf8)) as? [String: Any]
        let largeFiles = (scanBody?["large_files"] as? [[String: Any]]) ?? []
        #expect(largeFiles.contains { ($0["path"] as? String) == file.path })

        // 2) propose（真实 plan builder）产出安全计划
        let proposeTool = ProposeStoragePlanTool()
        let proposeResult = await proposeTool.call(
            input: [
                "scan_roots": [scanRoot.path],
                "surface": "run",
                "proposals": [[
                    "source": file.path,
                    "suggested_category": "documents",
                    "suggested_action": "move",
                    "target": target.path,
                    "reason": "document",
                    "confidence": "high",
                ]],
            ] as [String: Any],
            context: context(scanRoot.path)
        )
        #expect(!proposeResult.isError)
        let plan = try JSONDecoder().decode(StoragePlan.self, from: Data(proposeResult.content.utf8))
        let planItem = try #require(plan.items.first)

        // 3) execute（注入隔离 executor）→ 文件移动 + manifest completed
        let execResult = await executeTool.call(
            input: [
                "operation_id": plan.operationId,
                "scan_roots": [scanRoot.path],
                "items": [[
                    "action": planItem.action.rawValue,
                    "source": planItem.sourcePath,
                    "target": planItem.targetPath ?? "",
                ]],
            ] as [String: Any],
            context: context(scanRoot.path)
        )
        let manifest = try decode(execResult)
        #expect(manifest.status == .completed)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: target.path))

        // 4) undo → 文件回原位
        let undoResult = await undoTool.call(
            input: ["operation_id": plan.operationId] as [String: Any],
            context: context(scanRoot.path)
        )
        #expect(!undoResult.isError)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - trash → undo（隔离 trash，不碰真实 ~/.Trash）

    @Test("trash→undo 经隔离 trash 回拉；不碰真实 ~/.Trash（SEC：可恢复、非永久删除）")
    func e2e_trash_then_undo_from_isolated_trash() async throws {
        let root = try scratch("chain-trash")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let (executeTool, undoTool) = toolPair(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let file = scanRoot.appendingPathComponent("disposable.tmp")
        try writeFile(file, bytes: 6)

        let execResult = await executeTool.call(
            input: [
                "operation_id": "op-trash-iso",
                "scan_roots": [scanRoot.path],
                "items": [["action": "trash", "source": file.path]],
            ] as [String: Any],
            context: context(scanRoot.path)
        )
        let manifest = try decode(execResult)
        let item = try #require(manifest.items.first)
        let trashPath = try #require(item.trashResultPath)

        // SEC：trash 落隔离目录、可恢复、非永久删除；不碰真实废纸篓。
        #expect(trashPath.hasPrefix(trash.path))
        #expect(!trashPath.contains(".Trash"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: trashPath))

        // undo 从隔离 trash 回拉
        let undoResult = await undoTool.call(
            input: ["operation_id": "op-trash-iso"] as [String: Any],
            context: context(scanRoot.path)
        )
        #expect(!undoResult.isError)
        let undone = try decode(undoResult)
        #expect(undone.undoResults?.first?.outcome == .restored)
        #expect(FileManager.default.fileExists(atPath: file.path))   // 源恢复
        #expect(!FileManager.default.fileExists(atPath: trashPath))  // 从隔离 trash 移走
    }

    // MARK: - manifest 持久化

    @Test("execute 后 manifest 落盘可加载，字段完整")
    func e2e_manifest_persisted_after_execute() async throws {
        let root = try scratch("chain-persist")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let (executeTool, _) = toolPair(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let file = scanRoot.appendingPathComponent("report.pdf")
        let target = scanRoot.appendingPathComponent("Archive/report.pdf")
        try writeFile(file, bytes: 12)

        _ = await executeTool.call(
            input: [
                "operation_id": "op-persist",
                "scan_roots": [scanRoot.path],
                "items": [["action": "move", "source": file.path, "target": target.path]],
            ] as [String: Any],
            context: context(scanRoot.path)
        )

        // 经 store（execute 注入的同一实例）加载落盘 manifest
        let loaded = try #require(store.load(operationId: "op-persist"))
        #expect(loaded.status == .completed)
        #expect(loaded.completedAt != nil)
        #expect(loaded.items.first?.targetPath == target.path)
        #expect(loaded.items.first?.outcome == .succeeded)
    }

    // MARK: - createDirectory 幂等

    @Test("create_directory 经 tool 层两次都 succeeded（幂等）")
    func e2e_create_directory_idempotent() async throws {
        let root = try scratch("chain-mkdir")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let (executeTool, _) = toolPair(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let dir = scanRoot.appendingPathComponent("Archive/2026")

        let input: [String: Any] = [
            "operation_id": "op-mkdir",
            "scan_roots": [scanRoot.path],
            "items": [["action": "create_directory", "source": dir.path]],
        ]
        let r1 = try decode(await executeTool.call(input: input, context: context(scanRoot.path)))
        #expect(r1.items.first?.outcome == .succeeded)
        #expect(r1.status == .completed)
        #expect(FileManager.default.fileExists(atPath: dir.path))

        // 第二次（不同 op-id）：mkdir -p 幂等，仍 succeeded
        var input2 = input
        input2["operation_id"] = "op-mkdir-2"
        let r2 = try decode(await executeTool.call(input: input2, context: context(scanRoot.path)))
        #expect(r2.items.first?.outcome == .succeeded)
        #expect(r2.status == .completed)
    }

    // MARK: - 逐项独立失败（mixed batch）

    @Test("mixed batch：目标已存在的项 failed，其余 succeeded → partiallyFailed")
    func e2e_mixed_batch_partially_failed() async throws {
        let root = try scratch("chain-mixed")
        defer { cleanup(root) }
        let ops = root.appendingPathComponent("ops", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        let store = StorageE2EFixture.makeStore(opsDir: ops, home: root.path)
        let (executeTool, _) = toolPair(store: store, trash: trash)

        let scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        let good = scanRoot.appendingPathComponent("good.txt")
        let goodTarget = scanRoot.appendingPathComponent("out/good.txt")
        let bad = scanRoot.appendingPathComponent("bad.txt")
        let badTarget = scanRoot.appendingPathComponent("existing.txt")  // 预存在 → target_exists
        try writeFile(good, bytes: 8)
        try writeFile(bad, bytes: 8)
        try writeFile(badTarget, bytes: 1)

        let result = try decode(await executeTool.call(
            input: [
                "operation_id": "op-mixed",
                "scan_roots": [scanRoot.path],
                "items": [
                    ["action": "move", "source": good.path, "target": goodTarget.path],
                    ["action": "move", "source": bad.path, "target": badTarget.path],
                ],
            ] as [String: Any],
            context: context(scanRoot.path)
        ))

        #expect(result.status == .partiallyFailed)
        // good 成功移动
        #expect(FileManager.default.fileExists(atPath: goodTarget.path))
        // bad 未覆盖既有目标（内容仍是 1 字节）
        #expect((try? Data(contentsOf: URL(fileURLWithPath: badTarget.path)).count) == 1)
        let badItem = result.items.first { $0.sourcePath == bad.path }
        #expect(badItem?.outcome == .failed)
        #expect(badItem?.reason == "target_exists")
    }
}
