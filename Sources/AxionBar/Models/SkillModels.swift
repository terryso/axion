import Foundation

// MARK: - BarSkillSummary

struct BarSkillSummary: Codable, Equatable, Hashable, Sendable {
    let name: String
    let description: String
    let type: String?
    let parameterCount: Int
    let stepCount: Int
    let lastUsedAt: String?
    let executionCount: Int

    enum CodingKeys: String, CodingKey {
        case name, description, type
        case parameterCount = "parameter_count"
        case stepCount = "step_count"
        case lastUsedAt = "last_used_at"
        case executionCount = "execution_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        parameterCount = try container.decode(Int.self, forKey: .parameterCount)
        stepCount = try container.decode(Int.self, forKey: .stepCount)
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt)
        executionCount = try container.decode(Int.self, forKey: .executionCount)
    }

    init(name: String, description: String, type: String? = nil, parameterCount: Int, stepCount: Int, lastUsedAt: String? = nil, executionCount: Int = 0) {
        self.name = name
        self.description = description
        self.type = type
        self.parameterCount = parameterCount
        self.stepCount = stepCount
        self.lastUsedAt = lastUsedAt
        self.executionCount = executionCount
    }
}

// MARK: - BarSkillDetail

struct BarSkillDetail: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let type: String?
    let version: Int
    let parameters: [BarSkillParameter]
    let stepCount: Int
    let lastUsedAt: String?
    let executionCount: Int

    enum CodingKeys: String, CodingKey {
        case name, description, type, version, parameters
        case stepCount = "step_count"
        case lastUsedAt = "last_used_at"
        case executionCount = "execution_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        version = try container.decode(Int.self, forKey: .version)
        parameters = try container.decode([BarSkillParameter].self, forKey: .parameters)
        stepCount = try container.decode(Int.self, forKey: .stepCount)
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt)
        executionCount = try container.decode(Int.self, forKey: .executionCount)
    }

    init(name: String, description: String, type: String? = nil, version: Int, parameters: [BarSkillParameter], stepCount: Int, lastUsedAt: String? = nil, executionCount: Int = 0) {
        self.name = name
        self.description = description
        self.type = type
        self.version = version
        self.parameters = parameters
        self.stepCount = stepCount
        self.lastUsedAt = lastUsedAt
        self.executionCount = executionCount
    }
}

// MARK: - BarSkillParameter

struct BarSkillParameter: Codable, Equatable, Sendable {
    let name: String
    let defaultValue: String?
    let description: String

    enum CodingKeys: String, CodingKey {
        case name
        case defaultValue = "default_value"
        case description
    }
}

// MARK: - BarSkillRunRequest

struct BarSkillRunRequest: Codable, Equatable, Sendable {
    let params: [String: String]?
}

// MARK: - BarSkillRunResponse

struct BarSkillRunResponse: Codable, Equatable, Sendable {
    let runId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}
