import Foundation

import AxionCore

/// Agent 提议的单个整理项（解析自 `propose_storage_plan` 工具入参）。
struct ProposedItem: Sendable, Equatable {
    /// 源路径（绝对路径）。
    let source: String
    /// Agent 给出的动态分类标签（如「发票与报销」「安装包可清理」）。
    let suggestedCategory: String?
    /// Agent 建议的动作。
    let suggestedAction: StorageAction
    /// 建议目标路径（可选）。
    let target: String?
    /// 分类/动作理由（Agent 提供）。
    let reason: String
    /// 置信度（Agent 提供）。
    let confidence: StorageConfidence

    init(
        source: String,
        suggestedCategory: String? = nil,
        suggestedAction: StorageAction,
        target: String? = nil,
        reason: String,
        confidence: StorageConfidence = .medium
    ) {
        self.source = source
        self.suggestedCategory = suggestedCategory
        self.suggestedAction = suggestedAction
        self.target = target
        self.reason = reason
        self.confidence = confidence
    }
}

/// Agent 输出解析 / 校验 / 物化 `StoragePlan` 的无状态构建器。
///
/// **安全核心**：逐项校验 `source` —— (1) 落在某个 `scanRoots` 之下；(2) 未被 `exclusions`
/// 排除；(3) 路径存在；(4) 非 symlink 目标。不满足 → 丢弃并记入 `summary`/`excludedNotes`，
/// **绝不**进入计划。对通过项就地重新读取单路径元数据，回填 `riskLevel`/`evidence`/`dataRisk`，
/// `approved` 强制为 `false`（AC #1、#4、#6）。
struct StoragePlanBuilder {

    func buildPlan(
        proposals: [ProposedItem],
        scanRoots: [URL],
        exclusions: StorageExclusions,
        surface: StorageSurface
    ) async -> StoragePlan {

        let standardizedRoots = scanRoots
            .map { StorageExclusions.standardize($0.path, home: exclusions.homeDirectory) }

        var items: [StoragePlanItem] = []
        var excludedNotes: [String] = []
        var highestRisk: RiskLevel = .low

        for proposal in proposals {
            let standardizedSource = StorageExclusions.standardize(proposal.source, home: exclusions.homeDirectory)

            // 校验 1：落在某个 scanRoot 之下
            guard standardizedRoots.contains(where: { standardizedSource == $0 || standardizedSource.hasPrefix($0 + "/") }) else {
                excludedNotes.append("outside_scan_roots: \(proposal.source)")
                continue
            }

            // 校验 2：未被排除。开发缓存根目录是例外：允许作为可重建目录整体清理，
            // 但不允许其内部子路径绕过排除规则。
            let (included, reason) = exclusions.evaluate(path: standardizedSource)
            let isAllowedDeveloperCacheRoot = !included
                && reason == "developer_cache"
                && exclusions.isDeveloperCacheRoot(standardizedSource)
                && Self.isDeveloperCacheActionAllowed(proposal.suggestedAction)
            guard included || isAllowedDeveloperCacheRoot else {
                excludedNotes.append("excluded(\(reason ?? "rule")): \(proposal.source)")
                continue
            }

            // 校验 3 + 4：路径存在 + 元数据可读；拒绝 symlink 目标
            guard let meta = readMetadata(for: standardizedSource) else {
                excludedNotes.append("missing_or_unreadable: \(proposal.source)")
                continue
            }
            if meta.isSymbolicLink {
                excludedNotes.append("symlink_target_not_followed: \(proposal.source)")
                continue
            }

            let riskLevel = Self.riskLevel(for: proposal.suggestedAction)
            let dataRisk = Self.dataRisk(for: meta.kind, isBundle: meta.isBundle)
            highestRisk = RiskLevel.max(highestRisk, riskLevel)

            let evidence = StorageEvidence(
                rule: Self.evidenceRule(category: proposal.suggestedCategory, kind: meta.kind, action: proposal.suggestedAction),
                source: proposal.reason,
                confidence: proposal.confidence
            )

            items.append(StoragePlanItem(
                action: proposal.suggestedAction,
                sourcePath: standardizedSource,
                targetPath: proposal.target.map { StorageExclusions.standardize($0, home: exclusions.homeDirectory) },
                sizeBytes: meta.sizeBytes,
                reason: proposal.reason,
                riskLevel: riskLevel,
                approved: false,
                evidence: evidence,
                dataRisk: dataRisk
            ))
        }

        let operationId = Self.generateOperationId()
        let createdAt = Self.nowISO8601()

        let accepted = items.count
        let rejected = proposals.count - accepted
        let summary = "Plan \(operationId): \(accepted) item(s) accepted, \(rejected) rejected. Risk: \(highestRisk.rawValue). All items require confirmation (approved=false); no action is taken without explicit approval."

        return StoragePlan(
            operationId: operationId,
            surface: surface,
            items: items,
            riskLevel: highestRisk,
            requiresConfirmation: true,
            reversible: true,
            summary: summary,
            createdAt: createdAt,
            excludedNotes: excludedNotes.isEmpty ? nil : excludedNotes
        )
    }

    // MARK: - Metadata (single-path re-read)

    private struct PathMetadata {
        let sizeBytes: Int64
        let kind: FileKind
        let isBundle: Bool
        let isSymbolicLink: Bool
    }

    private func readMetadata(for path: String) -> PathMetadata? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
        ]
        guard let rv = try? url.resourceValues(forKeys: keys) else { return nil }
        let typeIdentifier = (try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier

        let isDirectory = rv.isDirectory ?? false
        let isPackage = rv.isPackage ?? false
        let isSymbolicLink = rv.isSymbolicLink ?? false
        let ext = url.pathExtension.lowercased()
        let isBundle = isPackage
            || (!ext.isEmpty && StorageScanService.libraryExtensions.contains(ext))
        let isDeveloperCacheRoot = StorageExclusions.developerCacheRoot(for: path, home: NSHomeDirectory()) == path

        // 与扫描服务一致的体积口径
        let sizeBytes: Int64
        if isDeveloperCacheRoot && isDirectory && !isSymbolicLink {
            sizeBytes = max(
                Int64(rv.totalFileSize ?? rv.fileSize ?? 0),
                Self.directoryContentSize(url: url)
            )
        } else if isSymbolicLink {
            sizeBytes = Int64(rv.fileSize ?? 0)
        } else if isDirectory {
            sizeBytes = Int64(rv.totalFileSize ?? rv.fileSize ?? 0)
        } else {
            sizeBytes = Int64(rv.fileSize ?? 0)
        }

        let kind: FileKind
        if isDeveloperCacheRoot {
            kind = .developerCache
        } else {
            kind = FileKind.derive(fileExtension: ext.isEmpty ? nil : ext, typeIdentifier: typeIdentifier)
        }

        return PathMetadata(sizeBytes: sizeBytes, kind: kind, isBundle: isBundle, isSymbolicLink: isSymbolicLink)
    }

    private static func directoryContentSize(url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .totalFileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let rv = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isSymbolicLink == true {
                total += Int64(rv.fileSize ?? 0)
            } else if rv.isDirectory == true {
                continue
            } else {
                total += Int64(rv.totalFileSize ?? rv.fileSize ?? 0)
            }
        }
        return total
    }

    // MARK: - Risk / Evidence Derivation

    /// 操作风险（基于动作）。
    static func riskLevel(for action: StorageAction) -> RiskLevel {
        switch action {
        case .uninstallApp: return .high
        case .move, .trash: return .medium
        case .createDirectory, .scanOnly: return .low
        }
    }

    private static func isDeveloperCacheActionAllowed(_ action: StorageAction) -> Bool {
        action == .trash || action == .scanOnly
    }

    /// 数据风险（独立于操作风险；基于内容可恢复性）。
    static func dataRisk(for kind: FileKind, isBundle: Bool) -> DataRisk {
        switch kind {
        case .installer, .developerCache:
            return .low
        case .archive, .document, .image, .video, .audio:
            return .medium
        case .other:
            return isBundle ? .low : .medium
        }
    }

    private static func evidenceRule(category: String?, kind: FileKind, action: StorageAction) -> String {
        var parts: [String] = []
        if let category, !category.isEmpty { parts.append("category:\(category)") }
        parts.append("kind:\(kind.rawValue)")
        parts.append("action:\(action.rawValue)")
        return parts.joined(separator: "; ")
    }

    // MARK: - ID / Timestamp

    /// 运行时生成计划操作 ID（BMAD 编排脚本禁用 `Date.now/Math.random` 的限制不影响 Swift 运行时）。
    static func generateOperationId() -> String {
        "storage-" + UUID().uuidString
    }

    static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
