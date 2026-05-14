import Foundation

// MARK: - BarSkillSummary

struct BarSkillSummary: Codable, Equatable, Hashable, Sendable {
    let name: String
    let description: String
    let parameterCount: Int
    let stepCount: Int
    let lastUsedAt: String?
    let executionCount: Int

    enum CodingKeys: String, CodingKey {
        case name, description
        case parameterCount = "parameter_count"
        case stepCount = "step_count"
        case lastUsedAt = "last_used_at"
        case executionCount = "execution_count"
    }
}

// MARK: - BarSkillDetail

struct BarSkillDetail: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let version: Int
    let parameters: [BarSkillParameter]
    let stepCount: Int
    let lastUsedAt: String?
    let executionCount: Int

    enum CodingKeys: String, CodingKey {
        case name, description, version, parameters
        case stepCount = "step_count"
        case lastUsedAt = "last_used_at"
        case executionCount = "execution_count"
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
