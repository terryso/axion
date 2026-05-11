import Foundation
import JSONSchemaBuilder

@Schemable
struct SelectorQuery: Codable, Equatable, Sendable {
    let title: String?
    let titleContains: String?
    let axId: String?
    let role: String?
    let ordinal: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case titleContains = "title_contains"
        case axId = "ax_id"
        case role
        case ordinal
    }
}
