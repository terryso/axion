import Foundation

public enum RunState: String, Codable, CaseIterable, Equatable {
    case planning
    case executing
    case verifying
    case replanning
    case done
    case blocked
    case needsClarification
    case cancelled
    case failed
}
