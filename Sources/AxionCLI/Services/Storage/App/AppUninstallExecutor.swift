import Foundation

import AxionCore

/// `trashItem` 注入点（生产用真实 `FileManager.trashItem`；测试注入闭包 Mock，避免污染真实废纸篓）。
/// 返回实际落位路径（撤销依赖它）。
struct TrashPerforming: Sendable {
    let perform: @Sendable (URL) throws -> URL

    /// 生产实现：系统废纸篓（可恢复）。**绝不** `removeItem`（永久删除）。
    static let system = TrashPerforming { source in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &resulting)
        return resulting as URL? ?? source
    }
}

/// App 卸载执行实现（独立 executor，**不改 StorageExecutor**，语义差异大：需先退出 App、
/// bundleId 校验、support 数据联动）。
///
/// **安全核心**（对齐 39.2 `StorageExecutor`）：
/// - **草稿先行**：第一件事即写 `status = planned` 的 manifest 草稿到磁盘，再开始任何副作用。
/// - **纵深校验（AC #12）**：App bundle —— 路径 ∈ searchRoots、非系统保护、存在且为 `.app`、
///   bundleId 与磁盘 bundle 一致；任一失败 → bundle 项记 `failed` + reason 进 errors，**不移动**。
/// - **运行中先退出（AC #3）**：`app.isRunning` → graceful `appQuitter.terminate`；失败 → bundle 项
///   `failed` + `app_still_running`，**不移动**，不 force-kill。
/// - **support 数据纵深校验（AC #7/#8）**：`matchConfidence == low` → 拒绝；`dataRisk == forbidden`
///   → 拒绝；共享目录（`requiresExplicitApproval`）需 `defaultSelected == true`（已显式批准）；
///   路径必须位于 `~/Library` 之下（防伪造请求越界，与 39.2 executor 同理念）。
/// - **永不永久删除**：bundle + support 一律 `trashItem`（可恢复），**绝不** `removeItem`。
/// - **逐项独立**：单项失败不中断整批，记 `failed`/`skipped` + reason，继续其余项。
/// - **终态**：`(failed == 0 && errors.isEmpty) ? .completed : .partiallyFailed`（对齐 39.2 状态机）。
final class AppUninstallExecutor: AppUninstallExecuting, Sendable {

    private let manifestStore: StorageManifestStore
    private let appQuitter: AppQuitting
    private let trashPerformer: TrashPerforming

    init(manifestStore: StorageManifestStore, appQuitter: AppQuitting, trashPerformer: TrashPerforming = .system) {
        self.manifestStore = manifestStore
        self.appQuitter = appQuitter
        self.trashPerformer = trashPerformer
    }

    func execute(_ request: AppUninstallExecuteRequest) async -> AppUninstallExecuteResult {
        let createdAt = Self.nowISO8601()
        let home = request.homeDirectory
        let approvedByUser = "bundle=\(request.uninstallBundle), \(request.supportDataItems.count) support item(s) approved via \(request.surface.rawValue)"

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

        // --- App bundle 卸载（AC #9）---
        if request.uninstallBundle {
            let per = await uninstallBundle(request.app, searchRoots: request.searchRoots, home: home, createdAt: createdAt)
            manifest.items.append(per.item)
            switch per.item.outcome {
            case .succeeded: succeeded += 1
            case .skipped: skipped += 1
            case .failed: failed += 1
            }
            if let err = per.error { manifest.errors.append(err) }
            if manifest.status == .planned { manifest.status = .executing }
            manifestStore.trySave(manifest)
        }

        // --- 已批准 support 数据项 ---
        for item in request.supportDataItems {
            let per = trashSupportItem(item, home: home, createdAt: createdAt)
            manifest.items.append(per.item)
            switch per.item.outcome {
            case .succeeded: succeeded += 1
            case .skipped: skipped += 1
            case .failed: failed += 1
            }
            if let err = per.error { manifest.errors.append(err) }
            if manifest.status == .planned { manifest.status = .executing }
            manifestStore.trySave(manifest)
        }

        // 终态（对齐 39.2 状态机：completed 仅当无失败且无丢弃项）。
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

        return AppUninstallExecuteResult(manifest: manifest, succeeded: succeeded, skipped: skipped, failed: failed)
    }

    // MARK: - Bundle uninstall (AC #3, #9, #12)

    private struct Performed {
        let item: StorageManifestItem
        let error: String?
    }

    private func uninstallBundle(_ app: AppCandidate, searchRoots: [URL], home: String, createdAt: String) async -> Performed {
        let bundlePath = StorageExclusions.standardize(app.bundlePath, home: home)
        let evidence = StorageEvidence(rule: "app_bundle", source: "\(app.bundleIdentifier) \(app.displayName)", confidence: .high)
        let size = Self.readSize(path: bundlePath)

        // AC #12 纵深校验：失败 → bundle 项 failed + reason 进 errors，不移动。
        if let reject = Self.validateBundle(path: bundlePath, app: app, searchRoots: searchRoots) {
            return Performed(item: StorageManifestItem(
                action: .uninstallApp, sourcePath: bundlePath, sizeBytes: size,
                outcome: .failed, reason: reject, evidence: evidence, approvedAt: createdAt
            ), error: reject)
        }

        // AC #3：运行中先 graceful 退出；失败 → 不移动，不 force-kill。
        if app.isRunning {
            let terminated = await appQuitter.terminate(bundleIdentifier: app.bundleIdentifier)
            if !terminated {
                let reason = "app_still_running"
                return Performed(item: StorageManifestItem(
                    action: .uninstallApp, sourcePath: bundlePath, sizeBytes: size,
                    outcome: .failed, reason: reason, evidence: evidence, approvedAt: createdAt
                ), error: reason)
            }
        }

        // 移入废纸篓（AC #9）——绝不 removeItem。
        do {
            let trashPath = try trashPerformer.perform(URL(fileURLWithPath: bundlePath))
            return Performed(item: StorageManifestItem(
                action: .uninstallApp, sourcePath: bundlePath, trashResultPath: trashPath.path,
                sizeBytes: size, outcome: .succeeded, evidence: evidence, approvedAt: createdAt
            ), error: nil)
        } catch {
            let reason = "trash_failed: \(error.localizedDescription)"
            return Performed(item: StorageManifestItem(
                action: .uninstallApp, sourcePath: bundlePath, sizeBytes: size,
                outcome: .failed, reason: reason, evidence: evidence, approvedAt: createdAt
            ), error: reason)
        }
    }

    // MARK: - Support data (AC #7, #8)

    private func trashSupportItem(_ item: SupportDataItem, home: String, createdAt: String) -> Performed {
        let path = StorageExclusions.standardize(item.path, home: home)
        let size = Self.readSize(path: path)
        let evidence = item.matchEvidence

        // 纵深校验：低置信度 / forbidden / 共享目录未显式批准 / 越界 ~/Library / 不存在 → skipped + reason 进 errors。
        if let reject = Self.validateSupportItem(item, path: path, home: home) {
            return Performed(item: StorageManifestItem(
                action: .trash, sourcePath: path, sizeBytes: size,
                outcome: .skipped, reason: reject, evidence: evidence, approvedAt: createdAt
            ), error: reject)
        }

        do {
            let trashPath = try trashPerformer.perform(URL(fileURLWithPath: path))
            return Performed(item: StorageManifestItem(
                action: .trash, sourcePath: path, trashResultPath: trashPath.path,
                sizeBytes: size, outcome: .succeeded, evidence: evidence, approvedAt: createdAt
            ), error: nil)
        } catch {
            let reason = "trash_failed: \(error.localizedDescription)"
            return Performed(item: StorageManifestItem(
                action: .trash, sourcePath: path, sizeBytes: size,
                outcome: .failed, reason: reason, evidence: evidence, approvedAt: createdAt
            ), error: reason)
        }
    }

    // MARK: - Validation (defense in depth, pure-ish; reads fs)

    /// App bundle 纵深校验（AC #12）。返回非 nil 即拒绝原因。
    static func validateBundle(path: String, app: AppCandidate, searchRoots: [URL]) -> String? {
        // 1. 路径 ∈ searchRoots
        if !AppUninstallPlanBuilder.isInside(path, searchRoots) {
            return "outside_applications_dirs: \(path)"
        }
        // 2. 非系统保护
        if app.isSystemProtected {
            return "system_protected: \(app.bundleIdentifier)"
        }
        // 3. 存在且为 .app
        guard FileManager.default.fileExists(atPath: path) else {
            return "bundle_missing: \(path)"
        }
        guard path.hasSuffix(".app") else {
            return "not_an_app_bundle: \(path)"
        }
        // 4. bundleId 匹配（读实际 bundle 的 CFBundleIdentifier 与 app 比较，纵深校验）
        guard !app.bundleIdentifier.isEmpty else {
            return "missing_bundle_identifier"
        }
        guard let bundle = Bundle(url: URL(fileURLWithPath: path)),
              let actualId = bundle.bundleIdentifier, !actualId.isEmpty else {
            return "bundle_unreadable: \(path)"
        }
        if actualId != app.bundleIdentifier {
            return "bundle_id_mismatch: \(actualId) != \(app.bundleIdentifier)"
        }
        return nil
    }

    /// support 数据项纵深校验。返回非 nil 即拒绝原因。
    ///
    /// 策略门（低置信度 / forbidden / 共享未批准）优先于路径与存在性：策略拒绝的项无论是否存在都按
    /// 策略原因记录，便于上游区分「不应执行」与「无法执行」。
    ///
    /// `home` 用于把路径限制在 `~/Library` 之下（与 39.2 executor 同理念的纵深防御）：所有合法
    /// support 路径都在 `~/Library`（`SupportDataScanService` 仅键控探测 `~/Library` 子路径，AC #13）。
    /// Agent 编造的越界路径（即便带低风险标志）一律拒绝，防止伪造请求把任意用户文件移入废纸篓。
    static func validateSupportItem(_ item: SupportDataItem, path: String, home: String) -> String? {
        // AC #7：低置信度不进可执行集
        if item.matchConfidence == .low {
            return "low_confidence_hint_only: \(path)"
        }
        // forbidden（云/Keychain）MVP 不处理
        if item.dataRisk == .forbidden {
            return "forbidden_category: \(path)"
        }
        // AC #8：共享目录需 defaultSelected == true（视作已被显式批准）
        if item.requiresExplicitApproval && !item.defaultSelected {
            return "shared_directory_not_approved: \(path)"
        }
        // 纵深防御：support 数据必须位于 ~/Library 之下（合法 support 路径全集都在此）。
        let libRoot = StorageExclusions.standardize(home + "/Library", home: home)
        if path != libRoot && !path.hasPrefix(libRoot + "/") {
            return "outside_user_library: \(path)"
        }
        // 存在性（操作性校验放最后）
        if !FileManager.default.fileExists(atPath: path) {
            return "source_missing: \(path)"
        }
        return nil
    }

    // MARK: - Helpers

    private static func readSize(path: String) -> Int64 {
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

    private static func summary(operationId: String, succeeded: Int, skipped: Int, failed: Int, dropped: Int) -> String {
        "Manifest \(operationId): \(succeeded) succeeded, \(skipped) skipped, \(failed) failed, \(dropped) dropped. App uninstall executor."
    }
}
