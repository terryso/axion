import Foundation
import Testing
@testable import AxionCore

// [P0] Codable round-trip and factory methods
// [P1] Optional field variations and equality

@Suite("VerificationResult")
struct VerificationResultTests {

    // MARK: - P0 Codable Round-Trip (AC3, AC4, AC5)

    @Test("verificationResult done round trip preserves all fields")
    func verificationResultDoneRoundTripPreservesAllFields() throws {
        let original = VerificationResult(
            state: .done,
            reason: "Task completed successfully",
            screenshotBase64: "iVBORwkgAAAANSUhEUg==",
            axTreeSnapshot: "{\"role\": \"AXWindow\", \"title\": \"Calculator\"}"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerificationResult.self, from: data)
        #expect(decoded == original)
        #expect(decoded.state == .done)
        #expect(decoded.reason == "Task completed successfully")
        #expect(decoded.screenshotBase64 == "iVBORwkgAAAANSUhEUg==")
        #expect(decoded.axTreeSnapshot == "{\"role\": \"AXWindow\", \"title\": \"Calculator\"}")
    }

    @Test("verificationResult blocked round trip preserves all fields")
    func verificationResultBlockedRoundTripPreservesAllFields() throws {
        let original = VerificationResult(
            state: .blocked,
            reason: "Application crashed unexpectedly",
            screenshotBase64: nil,
            axTreeSnapshot: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerificationResult.self, from: data)
        #expect(decoded == original)
        #expect(decoded.state == .blocked)
        #expect(decoded.reason == "Application crashed unexpectedly")
        #expect(decoded.screenshotBase64 == nil)
        #expect(decoded.axTreeSnapshot == nil)
    }

    @Test("verificationResult needsClarification round trip preserves all fields")
    func verificationResultNeedsClarificationRoundTripPreservesAllFields() throws {
        let original = VerificationResult(
            state: .needsClarification,
            reason: "Multiple calculators found; which one?",
            screenshotBase64: "abc123",
            axTreeSnapshot: "{\"elements\": []}"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerificationResult.self, from: data)
        #expect(decoded == original)
        #expect(decoded.state == .needsClarification)
    }

    // MARK: - P0 Factory Methods (AC3, AC4, AC5)

    @Test("verificationResult done factory method correct state")
    func verificationResultDoneFactoryMethodCorrectState() {
        let result = VerificationResult.done(reason: "Calculator shows 391")
        #expect(result.state == .done)
        #expect(result.reason == "Calculator shows 391")
    }

    @Test("verificationResult blocked factory method correct state")
    func verificationResultBlockedFactoryMethodCorrectState() {
        let result = VerificationResult.blocked(reason: "Element not found")
        #expect(result.state == .blocked)
        #expect(result.reason == "Element not found")
    }

    @Test("verificationResult needsClarification factory method correct state")
    func verificationResultNeedsClarificationFactoryMethodCorrectState() {
        let result = VerificationResult.needsClarification(reason: "Ambiguous target")
        #expect(result.state == .needsClarification)
        #expect(result.reason == "Ambiguous target")
    }

    // MARK: - P1 Optional Fields

    @Test("verificationResult done without optionals")
    func verificationResultDoneWithoutOptionals() {
        let result = VerificationResult.done()
        #expect(result.state == .done)
        #expect(result.reason == nil)
    }

    // MARK: - P1 Equality

    @Test("verificationResult equality same values")
    func verificationResultEqualitySameValues() {
        let a = VerificationResult(state: .done, reason: "ok", screenshotBase64: nil, axTreeSnapshot: nil)
        let b = VerificationResult(state: .done, reason: "ok", screenshotBase64: nil, axTreeSnapshot: nil)
        #expect(a == b)
    }

    @Test("verificationResult equality different reason")
    func verificationResultEqualityDifferentReason() {
        let a = VerificationResult(state: .done, reason: "ok", screenshotBase64: nil, axTreeSnapshot: nil)
        let b = VerificationResult(state: .done, reason: "different", screenshotBase64: nil, axTreeSnapshot: nil)
        #expect(a != b)
    }
}
