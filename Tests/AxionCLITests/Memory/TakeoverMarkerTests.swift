import Testing
import Foundation

@testable import AxionCLI

@Suite("TakeoverMarker")
struct TakeoverMarkerTests {

    // MARK: - InterventionReason Codable round-trip (Task 5.2)

    @Test("InterventionReason all cases Codable round-trip")
    func interventionReasonRoundTrip() throws {
        for reason in InterventionReason.allCases {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(InterventionReason.self, from: data)
            #expect(decoded == reason)
        }
    }

    @Test("InterventionReason raw values use snake_case")
    func interventionReasonRawValues() {
        #expect(InterventionReason.plannerBlocked.rawValue == "planner_blocked")
        #expect(InterventionReason.needsClarification.rawValue == "needs_clarification")
        #expect(InterventionReason.loginOr2fa.rawValue == "login_or_2fa")
        #expect(InterventionReason.unknown.rawValue == "unknown")
    }

    // MARK: - classifyReason keyword mapping (Task 5.3)

    @Test("classifyReason maps 'blocked' to plannerBlocked")
    func classifyBlocked() {
        #expect(InterventionReason.classifyReason("Agent is blocked") == .plannerBlocked)
        #expect(InterventionReason.classifyReason("stuck in loop") == .plannerBlocked)
    }

    @Test("classifyReason maps 'clarif' to needsClarification")
    func classifyClarification() {
        #expect(InterventionReason.classifyReason("Needs clarification") == .needsClarification)
    }

    @Test("classifyReason maps 'foreground' to foregroundRequired")
    func classifyForeground() {
        #expect(InterventionReason.classifyReason("Requires foreground access") == .foregroundRequired)
    }

    @Test("classifyReason maps 'repeat' to repeatedActionFailure")
    func classifyRepeat() {
        #expect(InterventionReason.classifyReason("Repeated action failure") == .repeatedActionFailure)
    }

    @Test("classifyReason maps 'verif' to verificationFailed")
    func classifyVerification() {
        #expect(InterventionReason.classifyReason("Verification failed") == .verificationFailed)
    }

    @Test("classifyReason maps 'permission' to permissionPrompt")
    func classifyPermission() {
        #expect(InterventionReason.classifyReason("Permission denied") == .permissionPrompt)
        #expect(InterventionReason.classifyReason("Access restricted") == .permissionPrompt)
    }

    @Test("classifyReason maps 'confirm' to confirmationDialog")
    func classifyConfirm() {
        #expect(InterventionReason.classifyReason("Confirm dialog appeared") == .confirmationDialog)
        #expect(InterventionReason.classifyReason("dialog box") == .confirmationDialog)
    }

    @Test("classifyReason maps 'login' to loginOr2fa")
    func classifyLogin() {
        #expect(InterventionReason.classifyReason("Login required") == .loginOr2fa)
        #expect(InterventionReason.classifyReason("2FA verification") == .loginOr2fa)
        #expect(InterventionReason.classifyReason("Password prompt") == .loginOr2fa)
    }

    @Test("classifyReason maps 'captcha' to captcha")
    func classifyCaptcha() {
        #expect(InterventionReason.classifyReason("Captcha detected") == .captcha)
    }

    @Test("classifyReason maps 'modal' to nativeModal")
    func classifyModal() {
        #expect(InterventionReason.classifyReason("Modal dialog") == .nativeModal)
        #expect(InterventionReason.classifyReason("popup window") == .nativeModal)
    }

    @Test("classifyReason maps 'confidence' to lowConfidence")
    func classifyConfidence() {
        #expect(InterventionReason.classifyReason("Low confidence") == .lowConfidence)
        #expect(InterventionReason.classifyReason("Unsure about action") == .lowConfidence)
    }

    @Test("classifyReason maps 'unexpected' to unexpectedScreenChange")
    func classifyUnexpected() {
        #expect(InterventionReason.classifyReason("Unexpected error") == .unexpectedScreenChange)
        #expect(InterventionReason.classifyReason("Screen change detected") == .unexpectedScreenChange)
    }

    @Test("classifyReason maps 'destructive' to destructiveActionRisk")
    func classifyDestructive() {
        #expect(InterventionReason.classifyReason("Destructive action") == .destructiveActionRisk)
        #expect(InterventionReason.classifyReason("Danger zone") == .destructiveActionRisk)
    }

    @Test("classifyReason maps 'user request' to userRequestedTakeover")
    func classifyUserRequest() {
        #expect(InterventionReason.classifyReason("User requested takeover") == .userRequestedTakeover)
    }

    @Test("classifyReason returns unknown for unrecognized input")
    func classifyUnknown() {
        #expect(InterventionReason.classifyReason("something else") == .unknown)
        #expect(InterventionReason.classifyReason("") == .unknown)
    }

    @Test("classifyReason is case insensitive")
    func classifyCaseInsensitive() {
        #expect(InterventionReason.classifyReason("BLOCKED") == .plannerBlocked)
        #expect(InterventionReason.classifyReason("Permission Required") == .permissionPrompt)
    }

    // MARK: - TakeoverMarker.create() factory (Task 5.4)

    @Test("create() auto-fills schemaVersion=1 and createdAt")
    func createAutoFillsDefaults() {
        let marker = TakeoverMarker.create(
            runId: "run-123",
            outcome: .success,
            issue: "test issue",
            summary: "test summary"
        )
        #expect(marker.schemaVersion == 1)
        #expect(marker.runId == "run-123")
        #expect(marker.outcome == .success)
        #expect(marker.reasonType == .unknown)
        #expect(marker.feedback == nil)
        #expect(marker.duration == nil)
        #expect(marker.bundleId == nil)
        #expect(marker.appName == nil)
        #expect(marker.task == nil)
        #expect(!marker.createdAt.isEmpty)
        // createdAt should be valid ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(formatter.date(from: marker.createdAt) != nil)
    }

    @Test("create() passes through all parameters")
    func createPassesAllParameters() {
        let marker = TakeoverMarker.create(
            runId: "run-456",
            outcome: .failed,
            issue: "blocked by dialog",
            summary: "clicked OK",
            reasonType: .confirmationDialog,
            feedback: "used keyboard shortcut",
            duration: 42.5,
            bundleId: "com.apple.finder",
            appName: "Finder",
            task: "Open file"
        )
        #expect(marker.runId == "run-456")
        #expect(marker.outcome == .failed)
        #expect(marker.issue == "blocked by dialog")
        #expect(marker.summary == "clicked OK")
        #expect(marker.reasonType == .confirmationDialog)
        #expect(marker.feedback == "used keyboard shortcut")
        #expect(marker.duration == 42.5)
        #expect(marker.bundleId == "com.apple.finder")
        #expect(marker.appName == "Finder")
        #expect(marker.task == "Open file")
    }

    // MARK: - TakeoverMarker Codable round-trip (Task 5.5)

    @Test("TakeoverMarker Codable round-trip")
    func markerRoundTrip() throws {
        let marker = TakeoverMarker.create(
            runId: "run-789",
            outcome: .success,
            issue: "test",
            summary: "summary",
            reasonType: .loginOr2fa,
            feedback: "entered password",
            duration: 10.0,
            bundleId: "com.test.app",
            appName: "TestApp",
            task: "Do something"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(marker)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TakeoverMarker.self, from: data)

        #expect(decoded == marker)
    }

    @Test("TakeoverMarker CodingKeys use snake_case in JSON")
    func markerCodingKeysSnakeCase() throws {
        let marker = TakeoverMarker.create(
            runId: "run-abc",
            outcome: .success,
            issue: "issue",
            summary: "summary"
        )
        let data = try JSONEncoder().encode(marker)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["schema_version"] != nil)
        #expect(json["run_id"] != nil)
        #expect(json["reason_type"] != nil)
        #expect(json["created_at"] != nil)
        // Optional nil fields should be absent
        #expect(json["feedback"] == nil)
        #expect(json["duration"] == nil)
        #expect(json["bundle_id"] == nil)
    }

    // MARK: - toDictionary() (Task 5.5 supplementary)

    @Test("toDictionary() produces flat dictionary with snake_case keys")
    func toDictionarySnakeCase() {
        let marker = TakeoverMarker.create(
            runId: "run-dict",
            outcome: .success,
            issue: "test",
            summary: "test",
            feedback: "user feedback",
            duration: 5.0,
            bundleId: "com.test"
        )
        let dict = marker.toDictionary()

        #expect(dict["schema_version"] as? Int == 1)
        #expect(dict["run_id"] as? String == "run-dict")
        #expect(dict["outcome"] as? String == "success")
        #expect(dict["reason_type"] as? String == "unknown")
        #expect(dict["feedback"] as? String == "user feedback")
        #expect(dict["duration"] as? Double == 5.0)
        #expect(dict["bundle_id"] as? String == "com.test")
        #expect(dict["created_at"] != nil)
    }

    @Test("toDictionary() omits nil optional fields")
    func toDictionaryOmitsNil() {
        let marker = TakeoverMarker.create(
            runId: "run-minimal",
            outcome: .success,
            issue: "issue",
            summary: "summary"
        )
        let dict = marker.toDictionary()

        #expect(dict["feedback"] == nil)
        #expect(dict["duration"] == nil)
        #expect(dict["bundle_id"] == nil)
        #expect(dict["app_name"] == nil)
        #expect(dict["task"] == nil)
    }

    // MARK: - Duration conversion (Task 5.8)

    @Test("durationToSeconds converts ContinuousClock.Duration correctly")
    func durationToSecondsConversion() {
        let start = ContinuousClock.now
        // Simulate a known duration by creating one directly
        let duration = ContinuousClock.Duration(secondsComponent: 5, attosecondsComponent: 500_000_000_000_000_000)
        let seconds = TakeoverMarker.durationToSeconds(duration)
        #expect(seconds >= 5.0)
        #expect(seconds < 6.0)
    }

    @Test("durationToSeconds handles zero duration")
    func durationToSecondsZero() {
        let duration = ContinuousClock.Duration(secondsComponent: 0, attosecondsComponent: 0)
        let seconds = TakeoverMarker.durationToSeconds(duration)
        #expect(seconds == 0.0)
    }

    @Test("durationToSeconds handles sub-second precision")
    func durationToSecondsSubSecond() {
        let duration = ContinuousClock.Duration(secondsComponent: 0, attosecondsComponent: 500_000_000_000_000_000)
        let seconds = TakeoverMarker.durationToSeconds(duration)
        #expect(abs(seconds - 0.5) < 0.001)
    }
}
