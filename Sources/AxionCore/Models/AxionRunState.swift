import Foundation

public enum AxionRunState: String, Codable, Sendable, Equatable {
    case created
    case running
    case completed
    case failed

    public func isValidTransition(to target: AxionRunState) -> Bool {
        switch (self, target) {
        case (.created, .running): true
        case (.created, .failed): true
        case (.running, .completed): true
        case (.running, .failed): true
        default: false
        }
    }
}
