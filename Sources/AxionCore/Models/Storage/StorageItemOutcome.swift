import Foundation

/// 单项执行结果。
public enum StorageItemOutcome: String, Sendable, Equatable, Codable {
    case succeeded
    case failed
    case skipped
}

/// 单项撤销结果。
public enum StorageUndoOutcome: String, Sendable, Equatable, Codable {
    case restored
    case notRestored = "not_restored"
    case skipped
}
