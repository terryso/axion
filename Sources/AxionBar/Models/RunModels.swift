import Foundation

// MARK: - BarCreateRunRequest

struct BarCreateRunRequest: Codable, Equatable, Sendable {
    let task: String

    enum CodingKeys: String, CodingKey {
        case task
    }
}

// MARK: - BarCreateRunResponse

struct BarCreateRunResponse: Codable, Equatable, Sendable {
    let runId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}

// MARK: - BarRunStatusResponse

struct BarRunStatusResponse: Codable, Equatable, Sendable {
    let runId: String
    let status: String
    let task: String
    let totalSteps: Int?
    let durationMs: Int?
    let replanCount: Int?
    let submittedAt: String?
    let completedAt: String?
    let steps: [BarStepSummary]?
    let schemaVersion: Int?
    let ok: Bool?
    let live: Bool?
    let allowForeground: Bool?
    let criteria: String?
    let result: BarApiTaskResult?
    let intervention: BarInterventionData?
    let exitCode: Int?
    let error: String?
    let startedAt: String?
    let endedAt: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case task
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case replanCount = "replan_count"
        case submittedAt = "submitted_at"
        case completedAt = "completed_at"
        case steps
        case schemaVersion = "schema_version"
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try container.decode(String.self, forKey: .runId)
        status = try container.decode(String.self, forKey: .status)
        task = try container.decode(String.self, forKey: .task)
        totalSteps = try container.decodeIfPresent(Int.self, forKey: .totalSteps)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        replanCount = try container.decodeIfPresent(Int.self, forKey: .replanCount)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        steps = try container.decodeIfPresent([BarStepSummary].self, forKey: .steps)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        live = try container.decodeIfPresent(Bool.self, forKey: .live)
        allowForeground = try container.decodeIfPresent(Bool.self, forKey: .allowForeground)
        criteria = try container.decodeIfPresent(String.self, forKey: .criteria)
        result = try container.decodeIfPresent(BarApiTaskResult.self, forKey: .result)
        intervention = try container.decodeIfPresent(BarInterventionData.self, forKey: .intervention)
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
    }
}

// MARK: - BarStepSummary

struct BarStepSummary: Codable, Equatable, Sendable {
    let index: Int
    let tool: String
    let purpose: String
    let success: Bool
}

// MARK: - SSE Event Data Models

struct BarStepStartedData: Codable, Equatable, Sendable {
    let stepIndex: Int
    let tool: String

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
    }
}

struct BarStepCompletedData: Codable, Equatable, Sendable {
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

struct BarRunCompletedData: Codable, Equatable, Sendable {
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

// MARK: - BarSSEEvent

enum BarSSEEvent: Equatable, Sendable {
    case stepStarted(BarStepStartedData)
    case stepCompleted(BarStepCompletedData)
    case runCompleted(BarRunCompletedData)

    var eventType: String {
        switch self {
        case .stepStarted: return "step_started"
        case .stepCompleted: return "step_completed"
        case .runCompleted: return "run_completed"
        }
    }
}

// MARK: - StandardTaskOutput Compatibility Types

struct BarApiTaskResult: Codable, Equatable, Sendable {
    let kind: String
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

struct BarInterventionData: Codable, Equatable, Sendable {
    let reason: String
    let availableActions: [String]
    let blockingIssue: String

    enum CodingKeys: String, CodingKey {
        case reason
        case availableActions = "available_actions"
        case blockingIssue = "blocking_issue"
    }
}
