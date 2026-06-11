import Foundation

import AxionCore

/// 撤销实现：按 manifest **逆序**恢复（后执行的先还原），逐项独立 best-effort。
///
/// 恢复语义（AC #8 / #9）：
/// - `move`（原项 succeeded）：从 `targetPath` 移回 `sourcePath`。source 已存在 → 不覆盖；
///   target 缺失 → `target_missing`。
/// - `trash`（原项 succeeded）：从 `trashResultPath` 移回 `sourcePath`。source 已存在 → 不覆盖；
///   `trashResultPath` 缺失（如用户已清空废纸篓）→ `item_no_longer_in_trash`。
/// - `createDirectory`（原项 succeeded）：仅当目录**为空**时移除；非空 → `directory_not_empty`。
///   `FileManager.removeItem` **仅**用于此（空目录），永不用于其他永久删除。
/// - `scanOnly` / 原项 `failed` / `skipped`：撤销 `skipped`（无可恢复对象）。
///
/// 写回 manifest：`undoneAt` + `undoResults`（与 `items` 同序，逐项可审计），原子覆写。
/// 失败的恢复项**不回滚**已成功恢复项。
final class StorageUndoService: StorageUndoing, Sendable {

    private let manifestStore: StorageManifestStore

    init(manifestStore: StorageManifestStore) {
        self.manifestStore = manifestStore
    }

    func undo(_ request: UndoRequest) async -> UndoResult? {
        // 加载 manifest：指定 operationId 优先，否则取最近可撤销。
        let manifest: StorageManifest
        if let operationId = request.operationId, !operationId.isEmpty {
            guard let loaded = manifestStore.load(operationId: operationId) else { return nil }
            manifest = loaded
        } else {
            guard let loaded = manifestStore.mostRecentUndoable() else { return nil }
            manifest = loaded
        }

        // 逆序执行撤销（后执行的先还原，栈语义）；结果再反转为与 manifest.items 同序，便于逐项对照审计。
        let undoResults = Array(manifest.items.reversed().map { undoItem($0) }.reversed())

        var restored = 0
        var notRestored = 0
        var skipped = 0
        for result in undoResults {
            switch result.outcome {
            case .restored: restored += 1
            case .notRestored: notRestored += 1
            case .skipped: skipped += 1
            }
        }

        var updated = manifest
        updated.undoneAt = Self.nowISO8601()
        updated.undoResults = undoResults
        manifestStore.trySave(updated)

        return UndoResult(manifest: updated, restored: restored, notRestored: notRestored, skipped: skipped)
    }

    // MARK: - Per-item undo

    private func undoItem(_ item: StorageManifestItem) -> StorageUndoResult {
        // 仅原项 succeeded 才有可恢复对象；其余 → skipped。
        guard item.outcome == .succeeded else {
            return StorageUndoResult(sourcePath: item.sourcePath, action: item.action, outcome: .skipped)
        }

        switch item.action {
        case .move:
            return undoMove(item)
        case .trash:
            return undoTrash(item)
        case .createDirectory:
            return undoCreateDirectory(item)
        case .scanOnly, .uninstallApp:
            // scanOnly 无副作用；uninstallApp 不属本 Story（执行阶段已拒绝）。
            return StorageUndoResult(sourcePath: item.sourcePath, action: item.action, outcome: .skipped)
        }
    }

    private func undoMove(_ item: StorageManifestItem) -> StorageUndoResult {
        let source = item.sourcePath
        guard let target = item.targetPath else {
            return StorageUndoResult(sourcePath: source, action: .move, outcome: .notRestored, reason: "target_missing")
        }

        // source 已存在 → 不覆盖
        if FileManager.default.fileExists(atPath: source) {
            return StorageUndoResult(sourcePath: source, action: .move, outcome: .notRestored, reason: "source_already_exists")
        }
        // target 缺失 → 无法移回
        guard FileManager.default.fileExists(atPath: target) else {
            return StorageUndoResult(sourcePath: source, action: .move, outcome: .notRestored, reason: "target_missing")
        }

        do {
            try FileManager.default.moveItem(at: URL(fileURLWithPath: target), to: URL(fileURLWithPath: source))
            return StorageUndoResult(sourcePath: source, action: .move, outcome: .restored)
        } catch {
            return StorageUndoResult(sourcePath: source, action: .move, outcome: .notRestored, reason: "restore_failed: \(error.localizedDescription)")
        }
    }

    private func undoTrash(_ item: StorageManifestItem) -> StorageUndoResult {
        let source = item.sourcePath
        guard let trashResultPath = item.trashResultPath else {
            return StorageUndoResult(sourcePath: source, action: .trash, outcome: .notRestored, reason: "item_no_longer_in_trash")
        }

        // source 已存在 → 不覆盖
        if FileManager.default.fileExists(atPath: source) {
            return StorageUndoResult(sourcePath: source, action: .trash, outcome: .notRestored, reason: "source_already_exists")
        }
        // trashResultPath 缺失（如用户已清空废纸篓）→ 无法恢复（AC #9）
        guard FileManager.default.fileExists(atPath: trashResultPath) else {
            return StorageUndoResult(sourcePath: source, action: .trash, outcome: .notRestored, reason: "item_no_longer_in_trash")
        }

        do {
            try FileManager.default.moveItem(at: URL(fileURLWithPath: trashResultPath), to: URL(fileURLWithPath: source))
            return StorageUndoResult(sourcePath: source, action: .trash, outcome: .restored)
        } catch {
            return StorageUndoResult(sourcePath: source, action: .trash, outcome: .notRestored, reason: "restore_failed: \(error.localizedDescription)")
        }
    }

    private func undoCreateDirectory(_ item: StorageManifestItem) -> StorageUndoResult {
        let dir = item.sourcePath
        guard FileManager.default.fileExists(atPath: dir) else {
            // 目录已不存在（可能被用户手动删除）→ 视为已恢复态，跳过。
            return StorageUndoResult(sourcePath: dir, action: .createDirectory, outcome: .skipped, reason: "directory_already_absent")
        }

        // 仅当目录为空时移除（避免删用户后续放入的内容）。
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        guard contents.isEmpty else {
            return StorageUndoResult(sourcePath: dir, action: .createDirectory, outcome: .notRestored, reason: "directory_not_empty")
        }

        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: dir))
            return StorageUndoResult(sourcePath: dir, action: .createDirectory, outcome: .restored)
        } catch {
            return StorageUndoResult(sourcePath: dir, action: .createDirectory, outcome: .notRestored, reason: "remove_failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
