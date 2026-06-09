import Hummingbird
import OpenAgentSDK

typealias AgentSSEEvent = OpenAgentSDK.AgentSSEEvent

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
    let reviewSummary: String?

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
        costTelemetry: CostTelemetry? = nil,
        reviewSummary: String? = nil
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
        self.reviewSummary = reviewSummary
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
        reviewSummary = try container.decodeIfPresent(String.self, forKey: .reviewSummary)
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
        case reviewSummary = "review_summary"
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
    var reviewSummary: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case task
        case status
        case submittedAt = "submitted_at"
        case completedAt = "completed_at"
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case replanCount = "replan_count"
        case steps
        case costTelemetry = "cost_telemetry"
        case live
        case allowForeground = "allow_foreground"
        case criteria
        case result
        case intervention
        case exitCode = "exit_code"
        case error
        case schemaVersion = "schema_version"
        case reviewSummary = "review_summary"
    }

    // Legacy camelCase keys for backward-compatible decoding of pre-23.2 persisted data.
    private enum LegacyKeys: String, CodingKey {
        case runId, task, status, submittedAt, completedAt, totalSteps
        case durationMs, replanCount, steps, costTelemetry, live
        case allowForeground, criteria, result, intervention, exitCode
        case error, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)

        // Required fields: try snake_case first, fall back to camelCase
        runId = (try? container.decode(String.self, forKey: .runId))
            ?? (try? legacy.decode(String.self, forKey: .runId)) ?? ""
        task = (try? container.decode(String.self, forKey: .task))
            ?? (try? legacy.decode(String.self, forKey: .task)) ?? ""
        status = (try? container.decode(APIRunStatus.self, forKey: .status))
            ?? (try? legacy.decode(APIRunStatus.self, forKey: .status)) ?? .failed
        submittedAt = (try? container.decode(String.self, forKey: .submittedAt))
            ?? (try? legacy.decode(String.self, forKey: .submittedAt)) ?? ""

        // Optional fields
        completedAt = (try? container.decodeIfPresent(String.self, forKey: .completedAt))
            ?? (try? legacy.decodeIfPresent(String.self, forKey: .completedAt))
        totalSteps = (try? container.decodeIfPresent(Int.self, forKey: .totalSteps))
            ?? (try? legacy.decodeIfPresent(Int.self, forKey: .totalSteps))
            ?? 0
        durationMs = (try? container.decodeIfPresent(Int.self, forKey: .durationMs))
            ?? (try? legacy.decodeIfPresent(Int.self, forKey: .durationMs))
        replanCount = (try? container.decodeIfPresent(Int.self, forKey: .replanCount))
            ?? (try? legacy.decodeIfPresent(Int.self, forKey: .replanCount))
            ?? 0
        steps = (try? container.decodeIfPresent([StepSummary].self, forKey: .steps))
            ?? (try? legacy.decodeIfPresent([StepSummary].self, forKey: .steps))
            ?? []
        costTelemetry = (try? container.decodeIfPresent(CostTelemetry.self, forKey: .costTelemetry))
            ?? (try? legacy.decodeIfPresent(CostTelemetry.self, forKey: .costTelemetry))
        live = (try? container.decodeIfPresent(Bool.self, forKey: .live))
            ?? (try? legacy.decodeIfPresent(Bool.self, forKey: .live))
            ?? true
        allowForeground = (try? container.decodeIfPresent(Bool.self, forKey: .allowForeground))
            ?? (try? legacy.decodeIfPresent(Bool.self, forKey: .allowForeground))
            ?? false
        criteria = (try? container.decodeIfPresent(String.self, forKey: .criteria))
            ?? (try? legacy.decodeIfPresent(String.self, forKey: .criteria))
        result = (try? container.decodeIfPresent(ApiTaskResult.self, forKey: .result))
            ?? (try? legacy.decodeIfPresent(ApiTaskResult.self, forKey: .result))
        intervention = (try? container.decodeIfPresent(InterventionData.self, forKey: .intervention))
            ?? (try? legacy.decodeIfPresent(InterventionData.self, forKey: .intervention))
        exitCode = (try? container.decodeIfPresent(Int.self, forKey: .exitCode))
            ?? (try? legacy.decodeIfPresent(Int.self, forKey: .exitCode))
        error = (try? container.decodeIfPresent(String.self, forKey: .error))
            ?? (try? legacy.decodeIfPresent(String.self, forKey: .error))
        schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion))
            ?? (try? legacy.decodeIfPresent(Int.self, forKey: .schemaVersion))
            ?? 1
        reviewSummary = (try? container.decodeIfPresent(String.self, forKey: .reviewSummary))
    }

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
        schemaVersion: Int = 1,
        reviewSummary: String? = nil
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
        self.reviewSummary = reviewSummary
    }
}
