import Foundation

// MARK: - VerificationResult

/// The result of verifying whether a task has been completed after executing a batch of steps.
/// Contains the determined state (done, blocked, or needsClarification) along with optional
/// context data (screenshot, AX tree snapshot) captured during verification.
public struct VerificationResult: Codable, Equatable {
    public let state: RunState
    public let reason: String?
    public let screenshotBase64: String?
    public let axTreeSnapshot: String?

    public init(
        state: RunState,
        reason: String? = nil,
        screenshotBase64: String? = nil,
        axTreeSnapshot: String? = nil
    ) {
        self.state = state
        self.reason = reason
        self.screenshotBase64 = screenshotBase64
        self.axTreeSnapshot = axTreeSnapshot
    }

    // MARK: - Convenience Factory Methods

    /// Creates a verification result indicating the task is complete.
    public static func done(
        reason: String? = nil,
        screenshotBase64: String? = nil,
        axTreeSnapshot: String? = nil
    ) -> VerificationResult {
        VerificationResult(
            state: .done,
            reason: reason,
            screenshotBase64: screenshotBase64,
            axTreeSnapshot: axTreeSnapshot
        )
    }

    /// Creates a verification result indicating the task is blocked.
    public static func blocked(
        reason: String,
        screenshotBase64: String? = nil,
        axTreeSnapshot: String? = nil
    ) -> VerificationResult {
        VerificationResult(
            state: .blocked,
            reason: reason,
            screenshotBase64: screenshotBase64,
            axTreeSnapshot: axTreeSnapshot
        )
    }

    /// Creates a verification result indicating the task needs user clarification.
    public static func needsClarification(
        reason: String,
        screenshotBase64: String? = nil,
        axTreeSnapshot: String? = nil
    ) -> VerificationResult {
        VerificationResult(
            state: .needsClarification,
            reason: reason,
            screenshotBase64: screenshotBase64,
            axTreeSnapshot: axTreeSnapshot
        )
    }
}
