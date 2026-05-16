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
    let totalSteps: Int
    let durationMs: Int?
    let replanCount: Int
    let submittedAt: String
    let completedAt: String?
    let steps: [BarStepSummary]

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
