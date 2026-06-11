import Foundation

import AxionCore

/// App 卸载计划构建器（扫描阶段编排者）。依赖注入 `AppDiscovering` / `SupportDataScanning` /
/// `ExternalHintReading`，便于单测用 Mock（AC #2, #4, #6, #7, #8, #11）。
///
/// 编排流程：
/// 1. 发现候选 App（`appDiscoverer.discover`，已按置信度降序返回）。
/// 2. 多候选且无 high 唯一解 → `blockedReasons += ambiguous_match`（AC #2，不自动选第一个执行）。
/// 3. `isSystemProtected` → `system_protected`（AC #4）；bundle 不在 searchRoots 之下 →
///    `outside_applications_dirs`（4.1.3，与系统保护分开的两个独立信号）。
/// 4. 扫描 support 数据，按 `matchConfidence` 分流：`low` → `hintOnlySupportDataItems`（AC #7）。
/// 5. 聚合 `dataLossRisk`（取可执行项最高级）；高风险或存在未默认选中的高风险项 →
///    `requiresTypedConfirmation = true`（AC #6）。
/// 6. 读外部提示（best-effort 只读，不改风险策略，AC #11）。
struct AppUninstallPlanBuilder: Sendable {

    let supportDataScanner: SupportDataScanning
    let appDiscoverer: AppDiscovering
    let hintReader: ExternalHintReading

    init(supportDataScanner: SupportDataScanning, appDiscoverer: AppDiscovering, hintReader: ExternalHintReading) {
        self.supportDataScanner = supportDataScanner
        self.appDiscoverer = appDiscoverer
        self.hintReader = hintReader
    }

    func build(query: String, mode: AppUninstallMode, homeDirectory: String, searchRoots: [URL]) async -> AppUninstallPlan {
        let candidates = await appDiscoverer.discover(query: query, searchRoots: searchRoots)

        var blockedReasons: [String] = []
        let highConfidence = candidates.filter { $0.matchConfidence == .high }

        // AC #2：多候选且无 high 唯一解 → ambiguous_match；候选为空 → no_match 占位。
        let primaryApp: AppCandidate
        if candidates.isEmpty {
            primaryApp = AppCandidate(
                displayName: query, bundleIdentifier: "", bundlePath: "", version: "",
                sizeBytes: 0, isRunning: false, isSystemProtected: false, matchConfidence: .low
            )
            blockedReasons.append("no_match")
        } else {
            // discoverer 已按 high→medium 降序，首位即最高置信度。
            primaryApp = candidates[0]
            if candidates.count > 1 && highConfidence.count != 1 {
                blockedReasons.append("ambiguous_match")
            }
        }

        // AC #4：系统保护。
        if primaryApp.isSystemProtected {
            blockedReasons.append("system_protected")
        }

        // bundle 不在任一 searchRoots 之下 → outside_applications_dirs（独立于系统保护的信号）。
        if !primaryApp.bundlePath.isEmpty && !Self.isInside(primaryApp.bundlePath, searchRoots) {
            blockedReasons.append("outside_applications_dirs")
        }

        // AC #7：按 matchConfidence 分流。
        let rawItems = await supportDataScanner.scan(for: primaryApp, homeDirectory: homeDirectory)
        var supportDataItems: [SupportDataItem] = []
        var hintOnlySupportDataItems: [SupportDataItem] = []
        for item in rawItems {
            if item.matchConfidence == .low {
                hintOnlySupportDataItems.append(item)
            } else {
                supportDataItems.append(item)
            }
        }

        // AC #6 / 4.1.5：计划级数据丢失风险（取可执行项最高级，forbidden 归入 high）。
        let dataLossRisk = Self.aggregateDataLossRisk(supportDataItems)

        // AC #6 / 4.1.6：需 typed 确认 = 高风险，或存在未默认选中且需显式确认的高风险项。
        let hasUnapprovedHighRisk = supportDataItems.contains { !$0.defaultSelected && $0.requiresExplicitApproval }
        let requiresTypedConfirmation = (dataLossRisk == .high) || hasUnapprovedHighRisk

        // AC #11：外部提示（best-effort 只读）。
        let hints = hintReader.read(for: primaryApp)

        return AppUninstallPlan(
            app: primaryApp,
            candidates: candidates,
            uninstallMode: mode,
            supportDataItems: supportDataItems,
            hintOnlySupportDataItems: hintOnlySupportDataItems,
            dataLossRisk: dataLossRisk,
            requiresTypedConfirmation: requiresTypedConfirmation,
            blockedReasons: blockedReasons,
            externalUninstallHints: hints
        )
    }

    // MARK: - Pure helpers (unit-testable)

    /// `bundlePath` 是否位于 `searchRoots` 任一根之下（含根自身）。
    static func isInside(_ bundlePath: String, _ searchRoots: [URL]) -> Bool {
        let standardized = StorageExclusions.standardize(bundlePath, home: FileManager.default.homeDirectoryForCurrentUser.path)
        return searchRoots.contains { root in
            let rootPath = StorageExclusions.standardize(root.path, home: FileManager.default.homeDirectoryForCurrentUser.path)
            return standardized == rootPath || standardized.hasPrefix(rootPath + "/")
        }
    }

    /// 计划级数据丢失风险聚合：取可执行 support 项 `dataRisk` 最高级。
    /// `forbidden`（云/Keychain，MVP 不处理）归入 high，体现其在风险尺度上的高位。
    static func aggregateDataLossRisk(_ items: [SupportDataItem]) -> DataLossRisk {
        items.reduce(DataLossRisk.none) { acc, item in
            let mapped: DataLossRisk
            switch item.dataRisk {
            case .low: mapped = .low
            case .medium: mapped = .medium
            case .high, .forbidden: mapped = .high
            }
            return DataLossRisk.max(acc, mapped)
        }
    }
}
