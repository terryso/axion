import Hummingbird

/// Summary of a skill returned by `GET /v1/skills`.
struct SkillSummaryResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let name: String
    let description: String
    let type: String
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
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "recorded"
        parameterCount = try container.decode(Int.self, forKey: .parameterCount)
        stepCount = try container.decode(Int.self, forKey: .stepCount)
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt)
        executionCount = try container.decode(Int.self, forKey: .executionCount)
    }

    init(name: String, description: String, type: String = "recorded", parameterCount: Int, stepCount: Int, lastUsedAt: String? = nil, executionCount: Int = 0) {
        self.name = name
        self.description = description
        self.type = type
        self.parameterCount = parameterCount
        self.stepCount = stepCount
        self.lastUsedAt = lastUsedAt
        self.executionCount = executionCount
    }
}

/// Full detail of a skill returned by `GET /v1/skills/{name}`.
struct SkillDetailResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let name: String
    let description: String
    let type: String
    let version: Int
    let parameters: [SkillParameterResponse]
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
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "recorded"
        version = try container.decode(Int.self, forKey: .version)
        parameters = try container.decode([SkillParameterResponse].self, forKey: .parameters)
        stepCount = try container.decode(Int.self, forKey: .stepCount)
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt)
        executionCount = try container.decode(Int.self, forKey: .executionCount)
    }

    init(name: String, description: String, type: String = "recorded", version: Int, parameters: [SkillParameterResponse], stepCount: Int, lastUsedAt: String? = nil, executionCount: Int = 0) {
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

/// Skill parameter info in API responses.
struct SkillParameterResponse: Codable, Equatable, Sendable {
    let name: String
    let defaultValue: String?
    let description: String

    enum CodingKeys: String, CodingKey {
        case name
        case defaultValue = "default_value"
        case description
    }
}

/// Request body for `POST /v1/skills/{name}/run` (recorded skills).
struct SkillRunRequest: Codable, Equatable, Sendable {
    let params: [String: String]?
}

/// Request body for `POST /v1/skills/{name}/run` (prompt skills).
struct PromptSkillRunRequest: Codable, Equatable, Sendable {
    let task: String
    let params: [String: String]?
}

/// Response body for `POST /v1/skills/{name}/run`.
struct SkillRunResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let runId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}
