import Foundation

/// Classification of why the agent paused and handed control to the user.
///
/// Mapped from SDK `PausedData.reason` free-text via ``classifyReason(_:)``.
/// Raw values use snake_case for trace JSON compatibility.
enum InterventionReason: String, Codable, CaseIterable, Equatable, Sendable {
    case plannerBlocked = "planner_blocked"
    case needsClarification = "needs_clarification"
    case foregroundRequired = "foreground_required"
    case repeatedActionFailure = "repeated_action_failure"
    case verificationFailed = "verification_failed"
    case permissionPrompt = "permission_prompt"
    case confirmationDialog = "confirmation_dialog"
    case loginOr2fa = "login_or_2fa"
    case captcha = "captcha"
    case nativeModal = "native_modal"
    case lowConfidence = "low_confidence"
    case unexpectedScreenChange = "unexpected_screen_change"
    case destructiveActionRisk = "destructive_action_risk"
    case userRequestedTakeover = "user_requested_takeover"
    case unknown = "unknown"

    /// Maps SDK free-text pause reasons to structured enum values via keyword matching.
    static func classifyReason(_ reason: String) -> InterventionReason {
        let lower = reason.lowercased()
        if lower.contains("blocked") || lower.contains("stuck") { return .plannerBlocked }
        if lower.contains("clarif") { return .needsClarification }
        if lower.contains("foreground") { return .foregroundRequired }
        if lower.contains("repeat") { return .repeatedActionFailure }
        if lower.contains("login") || lower.contains("2fa") || lower.contains("password") { return .loginOr2fa }
        if lower.contains("verif") { return .verificationFailed }
        if lower.contains("permission") || lower.contains("access") { return .permissionPrompt }
        if lower.contains("modal") || lower.contains("popup") { return .nativeModal }
        if lower.contains("confirm") || lower.contains("dialog") { return .confirmationDialog }
        if lower.contains("captcha") { return .captcha }
        if lower.contains("confidence") || lower.contains("unsure") { return .lowConfidence }
        if lower.contains("unexpected") || lower.contains("screen change") { return .unexpectedScreenChange }
        if lower.contains("destructive") || lower.contains("danger") { return .destructiveActionRisk }
        if lower.contains("user request") { return .userRequestedTakeover }
        return .unknown
    }
}

/// Structured marker emitted when a takeover (pause/resume) event completes.
///
/// Captures full context — reason, user feedback, duration — for trace output
/// and Memory evidence enrichment.
struct TakeoverMarker: Codable, Equatable {
    let schemaVersion: Int
    let runId: String
    let outcome: TakeoverOutcome
    let issue: String
    let summary: String
    let reasonType: InterventionReason
    let feedback: String?
    let duration: TimeInterval?
    let bundleId: String?
    let appName: String?
    let task: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runId = "run_id"
        case outcome, issue, summary
        case reasonType = "reason_type"
        case feedback, duration
        case bundleId = "bundle_id"
        case appName = "app_name"
        case task
        case createdAt = "created_at"
    }

    /// Factory method — auto-fills `schemaVersion` (1) and `createdAt` (ISO 8601).
    static func create(
        runId: String,
        outcome: TakeoverOutcome,
        issue: String,
        summary: String,
        reasonType: InterventionReason = .unknown,
        feedback: String? = nil,
        duration: TimeInterval? = nil,
        bundleId: String? = nil,
        appName: String? = nil,
        task: String? = nil
    ) -> TakeoverMarker {
        return TakeoverMarker(
            schemaVersion: 1,
            runId: runId,
            outcome: outcome,
            issue: issue,
            summary: summary,
            reasonType: reasonType,
            feedback: feedback,
            duration: duration,
            bundleId: bundleId,
            appName: appName,
            task: task,
            createdAt: axionISO8601Formatter.string(from: Date())
        )
    }

    /// Converts a `ContinuousClock.Duration` to seconds (TimeInterval).
    static func durationToSeconds(_ duration: ContinuousClock.Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
