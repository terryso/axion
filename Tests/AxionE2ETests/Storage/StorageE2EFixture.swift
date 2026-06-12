import Foundation
import OpenAgentSDK

import AxionCore
@testable import AxionCLI

/// Story 39 E2E 测试共享 fixture。
///
/// **隔离与安全**（核心约束，所有 tool-chain 测试遵守）：
/// - 所有被操作文件都在测试**自造**的隔离临时目录（`NSTemporaryDirectory` + UUID）之下；
///   executor 只对传入 `items` 的 `source` 动手，**绝不碰用户真实文件**。
/// - manifest 落盘到隔离的 `opsDir`，**不污染** `~/.axion/storage-ops/`。
/// - `trash` 注入隔离 `TrashPerforming`（移入测试临时 trash 目录），**不碰真实 `~/.Trash`**。
/// - `removeItem` 永久删除仅由撤销 `createDirectory` 的空目录触发（见 `StorageUndoService`），且仅限空目录。
///
/// execute 与 undo 必须注入**同一** `StorageManifestStore` 实例，否则 undo 找不到 manifest。
enum StorageE2EFixture {

    /// 造隔离临时根目录（真实 FS；测试自造文件全部在其之下）。
    static func makeScratch(_ label: String) throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("axion-e2e-storage-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 删除整个临时目录（tearDown；幂等）。
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 写入定长字节文件（自动创建父目录）。
    static func writeFile(_ url: URL, bytes: Int = 8) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: url)
    }

    /// 共享 manifestStore（execute + undo 注入同一实例）。opsDir 隔离，不污染真实 `~/.axion/storage-ops/`。
    static func makeStore(opsDir: URL, home: String) -> StorageManifestStore {
        StorageManifestStore(storageOpsDir: opsDir.path, homeDirectory: home)
    }

    /// 隔离 trash 注入：把文件 `moveItem` 进临时 trash 目录、返回落位 URL（**不碰真实 `~/.Trash`**）。
    /// 范式同 `AppUninstallExecutorTests.makeMockTrash`。
    static func makeIsolatedTrash(_ trashDir: URL) -> TrashPerforming {
        TrashPerforming { source in
            try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
            let dest = trashDir.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
            try FileManager.default.moveItem(at: source, to: dest)
            return dest
        }
    }

    /// 构造 execute + undo 工具对，注入**同一** manifestStore + 隔离 trash。
    static func makeToolPair(
        store: StorageManifestStore,
        trashPerformer: TrashPerforming
    ) -> (execute: ExecuteStoragePlanTool, undo: UndoStorageOpTool) {
        let executor = StorageExecutor(manifestStore: store, trashPerformer: trashPerformer)
        let undoer = StorageUndoService(manifestStore: store)
        return (
            ExecuteStoragePlanTool(executor: executor),
            UndoStorageOpTool(undoer: undoer)
        )
    }

    /// `ToolResult.content`（JSON）解码为 `StorageManifest`（encode/decode 对称，CodingKeys 一致）。
    static func decodeManifest(_ result: ToolResult) throws -> StorageManifest {
        try JSONDecoder().decode(StorageManifest.self, from: Data(result.content.utf8))
    }

    /// 唯一 toolUseId 的 ToolContext。
    static func makeContext(cwd: String) -> ToolContext {
        ToolContext(cwd: cwd, toolUseId: "e2e-\(UUID().uuidString)")
    }
}
