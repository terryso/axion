import Foundation

// MARK: - StopCondition

struct StopCondition: Codable, Equatable {
    let type: StopType
    let value: String?
}

// MARK: - StopType

enum StopType: String, Codable {
    case windowAppears
    case windowDisappears
    case fileExists
    case textAppears
    case processExits
    case maxStepsReached
    case custom
}
