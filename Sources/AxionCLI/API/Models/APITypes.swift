import Foundation
import Hummingbird
import OpenAgentSDK

typealias AgentSSEEvent = OpenAgentSDK.AgentSSEEvent
typealias SKDEventBroadcaster = OpenAgentSDK.EventBroadcaster
typealias SDKConcurrencyLimiter = OpenAgentSDK.ConcurrencyLimiter

typealias APIRunStatus = OpenAgentSDK.APIRunStatus
typealias CreateRunRequest = OpenAgentSDK.CreateRunRequest
typealias StepSummary = OpenAgentSDK.StepSummary
typealias InterventionData = OpenAgentSDK.InterventionData

/// Unified output contract for all run-related API responses.
/// Replaces the previous CreateRunResponse and RunStatusResponse.
struct StandardTaskOutput: Codable, Equatable, Sendable, ResponseEncodable {
    let schemaVersion: Int
    let runId: String
    let task: String
    let status: APIRunStatus
    let ok: Bool
    let live: Bool
    let allowForeground: Bool
    let criteria: String?
    let result: ApiTaskResult?
    let intervention: InterventionData?
    let exitCode: Int?
    let error: String?
    let startedAt: String
    let endedAt: String?
    let steps: [StepSummary]
    let costTelemetry: CostTelemetry?

    init(
        schemaVersion: Int = 1,
        runId: String,
        task: String,
        status: APIRunStatus,
        ok: Bool = true,
        live: Bool = true,
        allowForeground: Bool = false,
        criteria: String? = nil,
        result: ApiTaskResult? = nil,
        intervention: InterventionData? = nil,
        exitCode: Int? = nil,
        error: String? = nil,
        startedAt: String,
        endedAt: String? = nil,
        steps: [StepSummary] = [],
        costTelemetry: CostTelemetry? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.task = task
        self.status = status
        self.ok = ok
        self.live = live
        self.allowForeground = allowForeground
        self.criteria = criteria
        self.result = result
        self.intervention = intervention
        self.exitCode = exitCode
        self.error = error
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.steps = steps
        self.costTelemetry = costTelemetry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runId = try container.decode(String.self, forKey: .runId)
        task = try container.decode(String.self, forKey: .task)
        status = try container.decode(APIRunStatus.self, forKey: .status)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        live = try container.decodeIfPresent(Bool.self, forKey: .live) ?? true
        allowForeground = try container.decodeIfPresent(Bool.self, forKey: .allowForeground) ?? false
        criteria = try container.decodeIfPresent(String.self, forKey: .criteria)
        result = try container.decodeIfPresent(ApiTaskResult.self, forKey: .result)
        intervention = try container.decodeIfPresent(InterventionData.self, forKey: .intervention)
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        steps = try container.decodeIfPresent([StepSummary].self, forKey: .steps) ?? []
        costTelemetry = try container.decodeIfPresent(CostTelemetry.self, forKey: .costTelemetry)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runId = "run_id"
        case task
        case status
        case ok
        case live
        case allowForeground = "allow_foreground"
        case criteria
        case result
        case intervention
        case exitCode = "exit_code"
        case error
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case steps
        case costTelemetry = "cost_telemetry"
    }
}

/// Kind of result returned by a completed task.
/// `answer` = informational (user asked to read/query),
/// `confirmation` = action performed (user asked to open/move/delete).
enum TaskResultKind: String, Codable, Equatable, Sendable, CaseIterable {
    case answer
    case confirmation
}

/// Result payload within StandardTaskOutput when a task completes successfully.
struct ApiTaskResult: Codable, Equatable, Sendable {
    let kind: TaskResultKind
    let title: String
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case body
        case createdAt = "created_at"
    }
}

/// Response body for `GET /v1/capabilities`.
struct CapabilitiesResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let version: String
    let supportedRunStatuses: [String]
    let supportedResultKinds: [String]
    let availableTools: [String]
    let maxConcurrentRuns: Int
    let features: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case supportedRunStatuses = "supported_run_statuses"
        case supportedResultKinds = "supported_result_kinds"
        case availableTools = "available_tools"
        case maxConcurrentRuns = "max_concurrent_runs"
        case features
    }
}

/// Response body for `POST /v1/runs` when the task is queued due to concurrency limits.
struct QueuedRunResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let runId: String
    let status: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case position
    }
}

typealias HealthResponse = OpenAgentSDK.HealthResponse
typealias APIErrorResponse = OpenAgentSDK.APIErrorResponse

/// Internal representation of a tracked run, stored in RunTracker.
struct TrackedRun: Codable, Equatable, Sendable {
    let runId: String
    let task: String
    var status: APIRunStatus
    let submittedAt: String
    var completedAt: String?
    var totalSteps: Int
    var durationMs: Int?
    var replanCount: Int
    var steps: [StepSummary]
    var costTelemetry: CostTelemetry?
    var live: Bool
    var allowForeground: Bool
    var criteria: String?
    var result: ApiTaskResult?
    var intervention: InterventionData?
    var exitCode: Int?
    var error: String?
    var schemaVersion: Int

    init(
        runId: String,
        task: String,
        status: APIRunStatus,
        submittedAt: String,
        completedAt: String? = nil,
        totalSteps: Int = 0,
        durationMs: Int? = nil,
        replanCount: Int = 0,
        steps: [StepSummary] = [],
        costTelemetry: CostTelemetry? = nil,
        live: Bool = true,
        allowForeground: Bool = false,
        criteria: String? = nil,
        result: ApiTaskResult? = nil,
        intervention: InterventionData? = nil,
        exitCode: Int? = nil,
        error: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.runId = runId
        self.task = task
        self.status = status
        self.submittedAt = submittedAt
        self.completedAt = completedAt
        self.totalSteps = totalSteps
        self.durationMs = durationMs
        self.replanCount = replanCount
        self.steps = steps
        self.costTelemetry = costTelemetry
        self.live = live
        self.allowForeground = allowForeground
        self.criteria = criteria
        self.result = result
        self.intervention = intervention
        self.exitCode = exitCode
        self.error = error
        self.schemaVersion = schemaVersion
    }
}

/// Response body for `GET /v1/settings/api-key`.
struct ApiKeyStatusResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let provider: String
    let available: Bool
    let source: String
    let maskedKey: String

    enum CodingKeys: String, CodingKey {
        case provider
        case available
        case source
        case maskedKey = "masked_key"
    }

    /// Mask an API key for safe display.
    /// Format: first 7 + "****" + last 4 (e.g. "sk-ant-****xxxx").
    /// Keys shorter than 11 chars: "****" + last 4. Empty keys: "".
    static func maskKey(_ key: String) -> String {
        if key.isEmpty { return "" }
        if key.count < 11 {
            let suffix = String(key.suffix(4))
            return "****\(suffix)"
        }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        return "\(prefix)****\(suffix)"
    }
}

/// Request body for `POST /v1/settings/api-key`.
struct SaveApiKeyRequest: Codable, Equatable, Sendable {
    let apiKey: String
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case provider
    }
}

/// Response body for `DELETE /v1/settings/api-key`.
struct DeleteApiKeyResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let provider: String
    let available: Bool
    let source: String
}

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

