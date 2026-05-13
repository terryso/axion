import Foundation
import JSONSchemaBuilder
import MCP

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

// MARK: - ParameterValue conformance for MCP @Parameter usage

extension SelectorQuery: ParameterValue {
    static var jsonSchemaType: String { "object" }

    static var jsonSchemaProperties: [String: Value] {
        [
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "title_contains": .object(["type": .string("string")]),
                "ax_id": .object(["type": .string("string")]),
                "role": .object(["type": .string("string")]),
                "ordinal": .object(["type": .string("integer")]),
            ]),
        ]
    }

    static var placeholderValue: SelectorQuery {
        SelectorQuery(title: nil, titleContains: nil, axId: nil, role: nil, ordinal: nil)
    }

    init?(parameterValue value: Value) {
        guard case .object(let obj) = value else { return nil }
        self.title = obj["title"].flatMap { if case .string(let v) = $0 { return v } else { return nil } }
        self.titleContains = obj["title_contains"].flatMap { if case .string(let v) = $0 { return v } else { return nil } }
        self.axId = obj["ax_id"].flatMap { if case .string(let v) = $0 { return v } else { return nil } }
        self.role = obj["role"].flatMap { if case .string(let v) = $0 { return v } else { return nil } }
        self.ordinal = obj["ordinal"].flatMap { if case .int(let v) = $0 { return v } else { return nil } }
    }
}
