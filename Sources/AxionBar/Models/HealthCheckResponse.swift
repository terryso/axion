import Foundation

struct HealthCheckResponse: Codable, Equatable, Sendable {
    let status: String
    let version: String
}
