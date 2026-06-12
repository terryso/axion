import Foundation

import AxionCore

/// 整理执行实现（`move` / `trash` / `createDirectory` / `scanOnly`）。
///
/// **安全核心**：
/// - **草稿先行**（AC #4）：第一件事即写 `status = planned` 的 manifest 草稿到磁盘，再开始任何副作用。
/// - **逐项重校验**（AC #5，纵深防御）：即使 39.1 `StoragePlanBuilder` 已校验过，本 executor 仍独立
///   校验每项 source —— scan_roots 前缀、`StorageExclusions.evaluate`、存在性（`createDirectory` 除外）、
///   非 symlink 目标；`action` 白名单只含 `move`/`trash`/`createDirectory`/`scanOnly`，遇 `uninstallApp`
///   或任何 `delete` 一律丢弃 + 记 `errors`，**绝不执行**。
/// - **永不永久删除**：`FileManager.removeItem` **仅**用于撤销 `createDirectory` 的空目录（见
///   `StorageUndoService`）；本 executor 不调用 `removeItem`。trash 经 `trashPerformer`（生产默认系统废纸篓，可恢复；测试可注入隔离目录）。
/// - **不覆盖**（AC #7）：`move` 遇 `target_exists` → `failed`，不调用 `moveItem`。
/// - **逐项独立**（AC #6）：单项失败不中断整批，记 `failed` + `reason`，继续其余项。
///
/// `final class ... : StorageExecuting, Sendable`：持不可变 `StorageManifestStore` 引用（Sendable），
/// 无可变状态。不调用真实 Helper、不发网络、不依赖 SDK Agent 循环。
final class StorageExecutor: StorageExecuting, Sendable {

    private let manifestStore: StorageManifestStore
    /// `trash` 注入点：生产 `.system` 走系统废纸篓（可恢复）；测试可注入隔离目录闭包，避免污染真实 `~/.Trash`。
    /// 复用 `AppUninstallExecutor.swift` 的 `TrashPerforming` 类型（同 module 可见）。
    private let trashPerformer: TrashPerforming
    /// `StorageAction` 白名单（执行允许的动作）。
    private static let allowedActions: Set<StorageAction> = [.move, .trash, .createDirectory, .scanOnly]

    init(manifestStore: StorageManifestStore, trashPerformer: TrashPerforming = .system) {
        self.manifestStore = manifestStore
        self.trashPerformer = trashPerformer
    }

    func execute(_ request: ExecuteRequest) async -> ExecuteResult {
        let createdAt = Self.nowISO8601()
        let approvedByUser = Self.approvalSummary(itemCount: request.items.count, surface: request.surface)
        let exclusions = StorageExclusions(
            excludedRoots: [],
            includeHidden: true,
            homeDirectory: request.homeDirectory
        )
        let standardizedRoots = request.scanRoots
            .map { StorageExclusions.standardize($0.path, home: request.homeDirectory) }

        // 草稿先行（AC #4）：副作用前先落盘 status = planned 的 manifest。
        var manifest = StorageManifest(
            operationId: request.operationId,
            createdAt: createdAt,
            surface: request.surface,
            userRequest: request.userRequest,
            approvedByUser: approvedByUser,
            items: [],
            status: .planned,
            errors: []
        )
        manifestStore.trySave(manifest)

        var succeeded = 0
        var skipped = 0
        var failed = 0

        for raw in request.items {
            // 重校验（AC #5）。违规项丢弃 + 记 errors，不执行。
            if let rejection = validate(raw, standardizedRoots: standardizedRoots, exclusions: exclusions) {
                manifest.errors.append(rejection)
                manifest.status = .executing
                manifestStore.trySave(manifest)
                continue
            }

            let executed = perform(raw, homeDirectory: request.homeDirectory, createdAt: createdAt)
            manifest.items.append(executed.item)
            switch executed.item.outcome {
            case .succeeded: succeeded += 1
            case .skipped: skipped += 1
            case .failed: failed += 1
            }

            // 逐项写盘：首项起即 executing（AC #4「逐项更新」）。
            if manifest.status == .planned { manifest.status = .executing }
            manifestStore.trySave(manifest)
        }

        // 终态：completed 仅当无执行失败且无纵深防御丢弃项（对齐 Dev Notes 状态机：
        // completed = 全部 succeeded/skipped；任一 failed 或被 errors 丢弃 → partiallyFailed）。
        // 否则一个「全部项被拒绝」的操作会误报 completed（items 空、errors 满），误导按 status 判定的调用方。
        manifest.status = (failed == 0 && manifest.errors.isEmpty) ? .completed : .partiallyFailed
        manifest.completedAt = Self.nowISO8601()
        manifest.summary = Self.summary(
            operationId: request.operationId,
            succeeded: succeeded,
            skipped: skipped,
            failed: failed,
            dropped: manifest.errors.count
        )
        manifestStore.trySave(manifest)

        return ExecuteResult(manifest: manifest, succeeded: succeeded, skipped: skipped, failed: failed)
    }

    // MARK: - Validation (defense in depth, AC #5)

    /// 返回非 nil 即拒绝原因（违规项丢弃 + 记 errors）。
    private func validate(
        _ item: ExecutionItem,
        standardizedRoots: [String],
        exclusions: StorageExclusions
    ) -> String? {
        // 1. action 白名单（拒绝 uninstallApp / 任何 delete；delete 无对应 StorageAction case，
        //    工具解析阶段即丢弃，此处对 uninstallApp 兜底）。
        guard Self.allowedActions.contains(item.action) else {
            return "action_not_allowed: \(item.action.rawValue)"
        }

        let source = StorageExclusions.standardize(item.source, home: exclusions.homeDirectory)

        // 2. 落在某个 scanRoot 之下
        guard standardizedRoots.contains(where: { source == $0 || source.hasPrefix($0 + "/") }) else {
            return "outside_scan_roots: \(item.source)"
        }

        // 3. 未被排除。开发缓存根目录是例外：允许整体移入废纸篓或 scan_only，
        // 但仍拒绝其内部子路径，避免绕过默认排除。
        let (included, rule) = exclusions.evaluate(path: source)
        let isAllowedDeveloperCacheRoot = !included
            && rule == "developer_cache"
            && exclusions.isDeveloperCacheRoot(source)
            && Self.isDeveloperCacheActionAllowed(item.action)
        guard included || isAllowedDeveloperCacheRoot else {
            return "excluded(\(rule ?? "rule")): \(item.source)"
        }

        // 4. 非 symlink 目标（不跟随，与 39.1 AC #2 一致）
        let url = URL(fileURLWithPath: source)
        let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if rv?.isSymbolicLink == true {
            return "symlink_target_not_followed: \(item.source)"
        }

        // 5. 存在性（move/trash/scanOnly 要求存在；createDirectory 是「创建」，不存在为正常）
        if item.action != .createDirectory, !FileManager.default.fileExists(atPath: source) {
            return "source_missing: \(item.source)"
        }

        return nil
    }

    private static func isDeveloperCacheActionAllowed(_ action: StorageAction) -> Bool {
        action == .trash || action == .scanOnly
    }

    // MARK: - Execution

    /// 单项执行（已通过校验）。返回 manifest item。
    private struct PerformedItem {
        let item: StorageManifestItem
    }

    private func perform(_ raw: ExecutionItem, homeDirectory: String, createdAt: String) -> PerformedItem {
        let source = StorageExclusions.standardize(raw.source, home: homeDirectory)
        let size = readSize(path: source)

        switch raw.action {
        case .scanOnly:
            // 已批准但无副作用 → skipped。
            return PerformedItem(item: StorageManifestItem(
                action: .scanOnly,
                sourcePath: source,
                sizeBytes: size,
                outcome: .skipped,
                reason: "scan_only_no_side_effect",
                evidence: raw.evidence,
                approvedAt: createdAt
            ))

        case .createDirectory:
            // mkdir -p；已存在视为成功（幂等）；路径存在且是文件 → failed。
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: source),
                    withIntermediateDirectories: true
                )
                return PerformedItem(item: StorageManifestItem(
                    action: .createDirectory,
                    sourcePath: source,
                    sizeBytes: 0,
                    outcome: .succeeded,
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            } catch {
                return PerformedItem(item: StorageManifestItem(
                    action: .createDirectory,
                    sourcePath: source,
                    sizeBytes: 0,
                    outcome: .failed,
                    reason: "create_directory_failed: \(error.localizedDescription)",
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            }

        case .move:
            let target = (raw.target.map { StorageExclusions.standardize($0, home: homeDirectory) }) ?? source

            // noop：target == source
            if target == source {
                return PerformedItem(item: StorageManifestItem(
                    action: .move,
                    sourcePath: source,
                    targetPath: target,
                    sizeBytes: size,
                    outcome: .skipped,
                    reason: "noop_source_is_target",
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            }

            // 不覆盖（AC #7）：target 已存在且 ≠ source → failed
            if FileManager.default.fileExists(atPath: target) {
                return PerformedItem(item: StorageManifestItem(
                    action: .move,
                    sourcePath: source,
                    targetPath: target,
                    sizeBytes: size,
                    outcome: .failed,
                    reason: "target_exists",
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            }

            // 自动创建中间目录（moveItem 不创建父目录）+ 移动
            do {
                let parent = (target as NSString).deletingLastPathComponent
                if !parent.isEmpty {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: parent),
                        withIntermediateDirectories: true
                    )
                }
                try FileManager.default.moveItem(
                    at: URL(fileURLWithPath: source),
                    to: URL(fileURLWithPath: target)
                )
                return PerformedItem(item: StorageManifestItem(
                    action: .move,
                    sourcePath: source,
                    targetPath: target,
                    sizeBytes: size,
                    outcome: .succeeded,
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            } catch {
                return PerformedItem(item: StorageManifestItem(
                    action: .move,
                    sourcePath: source,
                    targetPath: target,
                    sizeBytes: size,
                    outcome: .failed,
                    reason: "move_failed: \(error.localizedDescription)",
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            }

        case .trash:
            // 废纸篓（可恢复，trashPerformer 注入；生产 `.system` 走系统废纸篓，测试可注入隔离目录）。
            // 返回的落位路径（trashResultPath）是 undo 的恢复来源。
            do {
                let trashResultURL = try trashPerformer.perform(URL(fileURLWithPath: source))
                return PerformedItem(item: StorageManifestItem(
                    action: .trash,
                    sourcePath: source,
                    trashResultPath: trashResultURL.path,
                    sizeBytes: size,
                    outcome: .succeeded,
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            } catch {
                return PerformedItem(item: StorageManifestItem(
                    action: .trash,
                    sourcePath: source,
                    sizeBytes: size,
                    outcome: .failed,
                    reason: "trash_failed: \(error.localizedDescription)",
                    evidence: raw.evidence,
                    approvedAt: createdAt
                ))
            }

        case .uninstallApp:
            // 校验阶段已拒绝；此分支不可达（防御性兜底）。
            return PerformedItem(item: StorageManifestItem(
                action: .uninstallApp,
                sourcePath: source,
                sizeBytes: size,
                outcome: .skipped,
                reason: "action_not_allowed",
                evidence: raw.evidence,
                approvedAt: createdAt
            ))
        }
    }

    // MARK: - Helpers

    /// 就源路径重新读取体积（不信 Agent 入参；与 `StoragePlanBuilder` 同口径）。
    private func readSize(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let rv = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey,
        ]) else { return 0 }
        let isDirectory = rv.isDirectory ?? false
        if isDirectory {
            return Int64(rv.totalFileSize ?? rv.fileSize ?? 0)
        }
        return Int64(rv.fileSize ?? 0)
    }

    static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func approvalSummary(itemCount: Int, surface: StorageSurface) -> String {
        "\(itemCount) item(s) approved via \(surface.rawValue)"
    }

    private static func summary(operationId: String, succeeded: Int, skipped: Int, failed: Int, dropped: Int) -> String {
        "Manifest \(operationId): \(succeeded) succeeded, \(skipped) skipped, \(failed) failed, \(dropped) dropped. Status set from outcome and drop counts."
    }
}
