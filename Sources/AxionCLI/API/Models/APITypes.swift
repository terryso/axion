import Foundation
import Hummingbird

// MARK: - APIRunStatus

/// External-facing run status exposed via HTTP API.
/// Eight statuses aligned with the StandardTaskOutput contract.
enum APIRunStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case queued
    case running
    case interventionNeeded = "intervention_needed"
    case userTakeover = "user_takeover"
    case resuming
    case completed
    case failed
    case cancelled
}

// MARK: - CreateRunRequest

/// Request body for `POST /v1/runs`.
struct CreateRunRequest: Codable, Equatable, Sendable {
    let task: String
    let maxSteps: Int?
    let maxBatches: Int?
    let allowForeground: Bool?

    enum CodingKeys: String, CodingKey {
        case task
        case maxSteps = "max_steps"
        case maxBatches = "max_batches"
        case allowForeground = "allow_foreground"
    }

    init(task: String, maxSteps: Int? = nil, maxBatches: Int? = nil, allowForeground: Bool? = nil) {
        self.task = task
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.allowForeground = allowForeground
    }
}

// MARK: - StandardTaskOutput

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

// MARK: - TaskResultKind

/// Kind of result returned by a completed task.
/// `answer` = informational (user asked to read/query),
/// `confirmation` = action performed (user asked to open/move/delete).
enum TaskResultKind: String, Codable, Equatable, Sendable, CaseIterable {
    case answer
    case confirmation
}

// MARK: - ApiTaskResult

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

// MARK: - InterventionData

/// Intervention payload when a task enters takeover state.
struct InterventionData: Codable, Equatable, Sendable {
    let reason: String
    let availableActions: [String]
    let blockingIssue: String

    enum CodingKeys: String, CodingKey {
        case reason
        case availableActions = "available_actions"
        case blockingIssue = "blocking_issue"
    }
}

// MARK: - StepSummary

/// Summary of a single executed step within a run.
struct StepSummary: Codable, Equatable, Sendable {
    let index: Int
    let tool: String
    let purpose: String
    let success: Bool
}

// MARK: - HealthResponse

/// Response body for `GET /v1/health`.
struct HealthResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let status: String
    let version: String
}

// MARK: - CapabilitiesResponse

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

// MARK: - QueuedRunResponse

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

// MARK: - APIErrorResponse

/// Standard error response format for all API errors.
struct APIErrorResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let error: String
    let message: String
}

// MARK: - TrackedRun

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

    /// Convert to the external StandardTaskOutput contract.
    func toStandardOutput() -> StandardTaskOutput {
        StandardTaskOutput(
            schemaVersion: schemaVersion,
            runId: runId,
            task: task,
            status: status,
            ok: ![.failed, .cancelled, .interventionNeeded, .userTakeover].contains(status),
            live: live,
            allowForeground: allowForeground,
            criteria: criteria,
            result: result,
            intervention: intervention,
            exitCode: exitCode,
            error: error,
            startedAt: submittedAt,
            endedAt: completedAt,
            steps: steps,
            costTelemetry: costTelemetry
        )
    }
}

// MARK: - RunOptions

/// Options for running an agent task, derived from CreateRunRequest.
struct RunOptions: Codable, Equatable, Sendable {
    let task: String
    let maxSteps: Int?
    let maxBatches: Int?
    let allowForeground: Bool?

    init(task: String, maxSteps: Int? = nil, maxBatches: Int? = nil, allowForeground: Bool? = nil) {
        self.task = task
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.allowForeground = allowForeground
    }
}

// MARK: - SSE Event Types (Story 5.2)

/// Data payload for a `step_started` SSE event.
struct StepStartedData: Codable, Equatable, Sendable {
    let stepIndex: Int
    let tool: String

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
    }
}

/// Data payload for a `step_completed` SSE event.
struct StepCompletedData: Codable, Equatable, Sendable {
    let stepIndex: Int
    let tool: String
    let purpose: String
    let success: Bool
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
        case purpose
        case success
        case durationMs = "duration_ms"
    }
}

/// Data payload for a `run_completed` SSE event.
struct RunCompletedData: Codable, Equatable, Sendable {
    let runId: String
    let finalStatus: String
    let totalSteps: Int
    let durationMs: Int?
    let replanCount: Int

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case finalStatus = "final_status"
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case replanCount = "replan_count"
    }
}

// MARK: - Skill API Types (Story 10.3)

/// Summary of a skill returned by `GET /v1/skills`.
struct SkillSummaryResponse: Codable, Equatable, Sendable, ResponseEncodable {
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

/// Full detail of a skill returned by `GET /v1/skills/{name}`.
struct SkillDetailResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let name: String
    let description: String
    let version: Int
    let parameters: [SkillParameterResponse]
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

/// Request body for `POST /v1/skills/{name}/run`.
struct SkillRunRequest: Codable, Equatable, Sendable {
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

/// SSE event types emitted during agent execution.
enum SSEEvent: Equatable, Sendable {
    case stepStarted(StepStartedData)
    case stepCompleted(StepCompletedData)
    case runCompleted(RunCompletedData)

    /// The SSE event type name string.
    var eventType: String {
        switch self {
        case .stepStarted: return "step_started"
        case .stepCompleted: return "step_completed"
        case .runCompleted: return "run_completed"
        }
    }

    /// Encode this event as an SSE-formatted text string.
    /// - Parameter sequenceId: Sequential event ID for SSE `id:` field.
    /// - Returns: Formatted SSE text: `event: ...\ndata: ...\nid: ...\n\n`
    func encodeToSSE(sequenceId: Int) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        switch self {
        case .stepStarted(let d):
            data = try encoder.encode(d)
        case .stepCompleted(let d):
            data = try encoder.encode(d)
        case .runCompleted(let d):
            data = try encoder.encode(d)
        }

        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        return "event: \(eventType)\ndata: \(jsonString)\nid: \(sequenceId)\n\n"
    }
}
