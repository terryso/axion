import Foundation

/// 单条撤销记录。逆序恢复 `StorageManifest.items` 中每项时产生，写回 manifest `undoResults`。
public struct StorageUndoResult: Codable, Equatable, Sendable {

    /// 对应 manifest item 的源路径。
    public var sourcePath: String
    /// 对应 manifest item 的动作。
    public var action: StorageAction
    /// 单项撤销结果。
    public var outcome: StorageUndoOutcome
    /// 无法恢复的原因（`source_already_exists` / `target_missing` /
    /// `item_no_longer_in_trash` / `directory_not_empty` 等）。
    public var reason: String?

    enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
        case action
        case outcome
        case reason
    }

    public init(sourcePath: String, action: StorageAction, outcome: StorageUndoOutcome, reason: String? = nil) {
        self.sourcePath = sourcePath
        self.action = action
        self.outcome = outcome
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        action = try c.decodeIfPresent(StorageAction.self, forKey: .action) ?? .scanOnly
        outcome = try c.decodeIfPresent(StorageUndoOutcome.self, forKey: .outcome) ?? .skipped
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}
