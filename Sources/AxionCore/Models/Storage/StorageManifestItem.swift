import Foundation

/// 单条执行记录（manifest item）。字段与 `StoragePlanItem` 高度同构（action/source/
/// target/sizeBytes/evidence），但额外携带执行结果（`outcome`/`trashResultPath`/`reason`）。
///
/// 约定：`sourcePath` 是操作的主操作数——`move`/`trash`/`scanOnly` 指已存在的源文件；
/// `createDirectory` 指待创建的目录。`targetPath` 仅 `move` 使用（目标位置）。
/// `trashResultPath` 仅 `trash` 填写（`FileManager.trashItem` 返回的实际落位路径）。
public struct StorageManifestItem: Codable, Equatable, Sendable {

    /// 执行的动作（仅 `move`/`trash`/`createDirectory`/`scanOnly`；`uninstallApp`/`delete`
    /// 永不进入 manifest item —— executor 在白名单校验阶段即丢弃）。
    public var action: StorageAction
    /// 主操作数路径（标准化绝对路径）。
    public var sourcePath: String
    /// 目标路径（`move` 的目的地）。
    public var targetPath: String?
    /// 废纸篓实际落位路径（`trash` 专用，撤销依赖它）。
    public var trashResultPath: String?
    /// 字节大小（executor 执行前就源路径重新读取，不信 Agent 入参）。
    public var sizeBytes: Int64
    /// 单项执行结果。
    public var outcome: StorageItemOutcome
    /// 失败 / 跳过原因（如 `target_exists`、`noop_source_is_target`）。
    public var reason: String?
    /// 透传计划项证据。
    public var evidence: StorageEvidence?
    /// 批准时间（ISO8601；executor 写入 manifest 时回填）。
    public var approvedAt: String?

    enum CodingKeys: String, CodingKey {
        case action
        case sourcePath = "source_path"
        case targetPath = "target_path"
        case trashResultPath = "trash_result_path"
        case sizeBytes = "size_bytes"
        case outcome
        case reason
        case evidence
        case approvedAt = "approved_at"
    }

    public init(
        action: StorageAction,
        sourcePath: String,
        targetPath: String? = nil,
        trashResultPath: String? = nil,
        sizeBytes: Int64 = 0,
        outcome: StorageItemOutcome,
        reason: String? = nil,
        evidence: StorageEvidence? = nil,
        approvedAt: String? = nil
    ) {
        self.action = action
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.trashResultPath = trashResultPath
        self.sizeBytes = sizeBytes
        self.outcome = outcome
        self.reason = reason
        self.evidence = evidence
        self.approvedAt = approvedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decodeIfPresent(StorageAction.self, forKey: .action) ?? .scanOnly
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        targetPath = try c.decodeIfPresent(String.self, forKey: .targetPath)
        trashResultPath = try c.decodeIfPresent(String.self, forKey: .trashResultPath)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        outcome = try c.decodeIfPresent(StorageItemOutcome.self, forKey: .outcome) ?? .skipped
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        evidence = try c.decodeIfPresent(StorageEvidence.self, forKey: .evidence)
        approvedAt = try c.decodeIfPresent(String.self, forKey: .approvedAt)
    }
}
