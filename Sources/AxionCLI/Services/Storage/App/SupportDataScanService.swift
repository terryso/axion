import Foundation

import AxionCore

/// Support 数据扫描实现。
///
/// **精确探测**（AC #13）：维护 bundle-id 键控的候选路径模板表，逐个拼绝对路径 →
/// `FileManager.fileExists` 判存在 → 读 size。**禁止**对 `~/Library` 全量递归枚举；
/// **禁止**调用 `StorageExclusions.evaluate()`（对整个 `~/Library` 恒定排除，会误杀候选）。
/// 仅 `StorageExclusions.standardize(_:home:)` 做标准化。ByHost plist 与 Group Containers
/// 通过**特定子目录**的键控前缀匹配（bundle id / team id）探测，非 `~/Library` 递归。
///
/// 纯函数 `gradeEvidence` / `categoryToRisk` / `isSharedDirectory` 独立可测。
final class SupportDataScanService: SupportDataScanning, Sendable {

    init() {}

    func scan(for app: AppCandidate, homeDirectory: String) async -> [SupportDataItem] {
        let home = StorageExclusions.standardize(homeDirectory, home: homeDirectory)
        let lib = home + "/Library"
        let bundleId = app.bundleIdentifier
        let displayName = app.displayName

        // 直接键控路径候选：(category, subdir, name)
        let direct: [(SupportDataCategory, String, String)] = [
            (.cache, "Caches", bundleId),
            (.httpStorage, "HTTPStorages", bundleId),
            (.webKit, "WebKit", bundleId),
            (.logs, "Logs", bundleId),
            (.logs, "Logs", displayName),
            (.preferences, "Preferences", "\(bundleId).plist"),
            (.savedState, "Saved Application State", "\(bundleId).savedState"),
            (.applicationScripts, "Application Scripts", bundleId),
            (.container, "Containers", bundleId),
            (.applicationSupport, "Application Support", bundleId),
            (.applicationSupport, "Application Support", displayName),
            (.launchAgent, "LaunchAgents", "\(bundleId).plist"),
        ]

        var foundPaths: [(SupportDataCategory, String)] = []
        let fm = FileManager.default

        for (category, subdir, name) in direct where !name.isEmpty {
            let path = StorageExclusions.standardize("\(lib)/\(subdir)/\(name)", home: home)
            if fm.fileExists(atPath: path) {
                foundPaths.append((category, path))
            }
        }

        // ByHost plist：列出特定子目录 Preferences/ByHost，匹配 <bundleId>.*.plist（键控，非递归）
        if !bundleId.isEmpty {
            let byHostDir = StorageExclusions.standardize("\(lib)/Preferences/ByHost", home: home)
            if let entries = try? fm.contentsOfDirectory(atPath: byHostDir) {
                for entry in entries where entry.hasPrefix(bundleId + ".") && entry.hasSuffix(".plist") {
                    foundPaths.append((.preferences, StorageExclusions.standardize("\(byHostDir)/\(entry)", home: home)))
                    break  // 取首个键控命中即可（一台主机通常一个）
                }
            }
        }

        // Group Containers：列出特定子目录，匹配 <bundleId> 或 <teamId>.*（键控前缀）
        let groupDir = StorageExclusions.standardize("\(lib)/Group Containers", home: home)
        if let entries = try? fm.contentsOfDirectory(atPath: groupDir) {
            for entry in entries {
                let matches = entry == bundleId
                    || (app.teamIdentifier.map({ entry.hasPrefix($0 + ".") }) ?? false)
                guard matches else { continue }
                foundPaths.append((.groupContainer, StorageExclusions.standardize("\(groupDir)/\(entry)", home: home)))
            }
        }

        // 组装 SupportDataItem（证据分级 + 风险映射 + 共享目录保护 + defaultSelected 规则）
        return foundPaths.map { category, path in
            let size = Self.readSize(path: path)
            return Self.assembleItem(
                category: category,
                path: path,
                sizeBytes: size,
                bundleId: bundleId,
                displayName: displayName
            )
        }
    }

    // MARK: - Pure helpers (unit-testable, no FileManager state)

    /// 证据分级（纯函数）。
    ///
    /// - 路径末段 == bundle id / `<bundleId>.plist` / `<bundleId>.savedState` / `<bundleId>.*.plist`（ByHost）= **high**
    /// - 路径末段 == displayName / 含 bundle id 子串 = **medium**
    /// - Group Container 按 team id 命中（无法证明唯一归属）/ 仅名称相似 = **low**
    static func gradeEvidence(path: String, bundleId: String, displayName: String) -> (StorageConfidence, StorageEvidence) {
        let last = (path as NSString).lastPathComponent
        let lowerPath = path.lowercased()

        if !bundleId.isEmpty, last == bundleId {
            return (.high, StorageEvidence(rule: "bundle_id_keyed", source: "component=\(last)", confidence: .high))
        }
        if !bundleId.isEmpty, last == "\(bundleId).plist" || last == "\(bundleId).savedState" {
            return (.high, StorageEvidence(rule: "bundle_id_keyed", source: "component=\(last)", confidence: .high))
        }
        if !bundleId.isEmpty, last.hasPrefix(bundleId + "."), last.hasSuffix(".plist") {
            return (.high, StorageEvidence(rule: "bundle_id_keyed", source: "byhost_plist=\(last)", confidence: .high))
        }
        if !displayName.isEmpty, last == displayName {
            return (.medium, StorageEvidence(rule: "display_name_keyed", source: "component=\(last)", confidence: .medium))
        }
        if !bundleId.isEmpty, last.contains(bundleId) {
            return (.medium, StorageEvidence(rule: "bundle_id_substring", source: "component=\(last)", confidence: .medium))
        }
        if lowerPath.contains("/group containers/") {
            return (.low, StorageEvidence(rule: "group_container_team_id", source: "shared_group=\(last)", confidence: .low))
        }
        return (.low, StorageEvidence(rule: "name_similarity", source: "component=\(last)", confidence: .low))
    }

    /// 数据风险映射（纯函数）。
    ///
    /// cache/logs = low；httpStorage/webKit/preferences/savedState/applicationScripts = medium；
    /// applicationSupport/container/groupContainer/launchAgent = high；forbidden（云/Keychain）= forbidden。
    static func categoryToRisk(_ category: SupportDataCategory) -> DataRisk {
        switch category {
        case .cache, .logs:
            return .low
        case .httpStorage, .webKit, .preferences, .savedState, .applicationScripts:
            return .medium
        case .applicationSupport, .container, .groupContainer, .launchAgent:
            return .high
        case .forbidden:
            return .forbidden
        }
    }

    /// 共享目录保护（纯函数）：vendor 父目录、Group Containers（非唯一归属）、云同步目录 → true。
    static func isSharedDirectory(path: String, category: SupportDataCategory) -> Bool {
        let lower = path.lowercased()
        if lower.contains("/group containers/") {
            return true
        }
        // 云同步 / iCloud Drive / Dropbox / OneDrive
        let cloudMarkers = [
            "/library/mobile documents",
            "/library/cloudstorage",
            "/dropbox/",
            "/onedrive/",
        ]
        for marker in cloudMarkers where lower.contains(marker) {
            return true
        }
        // Application Support 下的多 App vendor 父目录（安全网：模板不主动探测 vendor 目录，
        // 但若候选命中 vendor 名，标记为共享）
        if category == .applicationSupport {
            let last = (path as NSString).lastPathComponent.lowercased()
            let knownVendors: Set<String> = ["google", "microsoft", "adobe", "mozilla", "slack", "jetbrains"]
            if knownVendors.contains(last) {
                return true
            }
        }
        return false
    }

    /// 组装单个 `SupportDataItem`（应用证据分级 + 风险 + 共享保护 + defaultSelected 规则）。
    /// 抽为 static 便于单测直接断言组装结果（不依赖文件系统）。
    static func assembleItem(
        category: SupportDataCategory,
        path: String,
        sizeBytes: Int64 = 0,
        bundleId: String,
        displayName: String
    ) -> SupportDataItem {
        let (matchConfidence, baseEvidence) = gradeEvidence(path: path, bundleId: bundleId, displayName: displayName)
        var dataRisk = categoryToRisk(category)
        let shared = isSharedDirectory(path: path, category: category)
        var requiresExplicitApproval = dataRisk == .high
        var defaultSelected = (dataRisk == .low) && (matchConfidence != .low)
        var evidence = baseEvidence

        if shared {
            // matchEvidence 追加 shared_directory 信号
            if !evidence.rule.contains("shared_directory") {
                evidence = StorageEvidence(
                    rule: "\(evidence.rule); shared_directory",
                    source: evidence.source,
                    confidence: evidence.confidence
                )
            }
            requiresExplicitApproval = true
            // 无法证明只归属目标 App（非 bundle-id 高置信度键控）→ 强制高风险、不默认选（AC #8）
            if matchConfidence != .high {
                dataRisk = .high
                defaultSelected = false
            }
        }

        return SupportDataItem(
            category: category,
            path: path,
            sizeBytes: sizeBytes,
            matchEvidence: evidence,
            matchConfidence: matchConfidence,
            dataRisk: dataRisk,
            defaultSelected: defaultSelected,
            requiresExplicitApproval: requiresExplicitApproval
        )
    }

    /// 就路径读取体积（与 `StorageExecutor.readSize` 同口径：目录走 `totalFileSize`）。
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
}
