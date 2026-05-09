import Foundation

// MARK: - StopCondition

public struct StopCondition: Codable, Equatable {
    public let type: StopType
    public let value: String?

    public init(type: StopType, value: String? = nil) {
        self.type = type
        self.value = value
    }
}

// MARK: - StopType

public enum StopType: String, Codable {
    case windowAppears
    case windowDisappears
    case fileExists
    case textAppears
    case processExits
    case maxStepsReached
    case custom
}
