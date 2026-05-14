import Foundation

/// A reusable skill compiled from a recording session.
public struct Skill: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let version: Int
    public let createdAt: Date
    public let sourceRecording: String
    public let parameters: [SkillParameter]
    public let steps: [SkillStep]

    enum CodingKeys: String, CodingKey {
        case name, description, version
        case createdAt = "created_at"
        case sourceRecording = "source_recording"
        case parameters, steps
    }

    public init(
        name: String,
        description: String,
        version: Int = 1,
        createdAt: Date,
        sourceRecording: String,
        parameters: [SkillParameter] = [],
        steps: [SkillStep]
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.createdAt = createdAt
        self.sourceRecording = sourceRecording
        self.parameters = parameters
        self.steps = steps
    }
}

/// A single step in a skill's execution sequence.
public struct SkillStep: Codable, Equatable, Sendable {
    public let tool: String
    public let arguments: [String: String]
    public let waitAfterSeconds: Double

    enum CodingKeys: String, CodingKey {
        case tool, arguments
        case waitAfterSeconds = "wait_after_seconds"
    }

    public init(tool: String, arguments: [String: String], waitAfterSeconds: Double = 0) {
        self.tool = tool
        self.arguments = arguments
        self.waitAfterSeconds = waitAfterSeconds
    }
}

/// A parameter definition for a skill.
public struct SkillParameter: Codable, Equatable, Sendable {
    public let name: String
    public let defaultValue: String?
    public let description: String

    enum CodingKeys: String, CodingKey {
        case name
        case defaultValue = "default_value"
        case description
    }

    public init(name: String, defaultValue: String? = nil, description: String) {
        self.name = name
        self.defaultValue = defaultValue
        self.description = description
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(defaultValue, forKey: .defaultValue)
        try container.encode(description, forKey: .description)
    }
}
