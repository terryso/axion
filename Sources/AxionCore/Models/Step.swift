import Foundation

// MARK: - Step

public struct Step: Codable, Equatable {
    public let index: Int
    public let tool: String
    public let parameters: [String: Value]
    public let purpose: String
    public let expectedChange: String

    public init(
        index: Int,
        tool: String,
        parameters: [String: Value],
        purpose: String,
        expectedChange: String
    ) {
        self.index = index
        self.tool = tool
        self.parameters = parameters
        self.purpose = purpose
        self.expectedChange = expectedChange
    }
}

// MARK: - Value

public enum Value: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case placeholder(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private static let codingTypeString = "string"
    private static let codingTypeInt = "int"
    private static let codingTypeBool = "bool"
    private static let codingTypePlaceholder = "placeholder"

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let v):
            try container.encode(Self.codingTypeString, forKey: .type)
            try container.encode(v, forKey: .value)
        case .int(let v):
            try container.encode(Self.codingTypeInt, forKey: .type)
            try container.encode(v, forKey: .value)
        case .bool(let v):
            try container.encode(Self.codingTypeBool, forKey: .type)
            try container.encode(v, forKey: .value)
        case .placeholder(let v):
            try container.encode(Self.codingTypePlaceholder, forKey: .type)
            try container.encode(v, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case Self.codingTypeString:
            self = .string(try container.decode(String.self, forKey: .value))
        case Self.codingTypeInt:
            self = .int(try container.decode(Int.self, forKey: .value))
        case Self.codingTypeBool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case Self.codingTypePlaceholder:
            self = .placeholder(try container.decode(String.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown Value type: \(type)"
            )
        }
    }
}
