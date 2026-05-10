import XCTest
@testable import AxionCore

// [P0] Codable round-trip and factory methods
// [P1] Optional field variations and equality

// MARK: - VerificationResult ATDD Tests

/// ATDD red-phase tests for VerificationResult model (Story 3-4 AC3, AC4, AC5).
/// These tests validate the VerificationResult struct: Codable conformance, Equatable,
/// and convenience factory methods for .done / .blocked / .needsClarification states.
///
/// TDD RED PHASE: These tests will not compile until VerificationResult is implemented
/// in Sources/AxionCore/Models/VerificationResult.swift.
final class VerificationResultTests: XCTestCase {

    // MARK: - P0 Codable Round-Trip (AC3, AC4, AC5)

    func test_verificationResult_doneRoundTrip_preservesAllFields() throws {
        let original = VerificationResult(
            state: .done,
            reason: "Task completed successfully",
            screenshotBase64: "iVBORwkgAAAANSUhEUg==",
            axTreeSnapshot: "{\"role\": \"AXWindow\", \"title\": \"Calculator\"}"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerificationResult.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.state, .done)
        XCTAssertEqual(decoded.reason, "Task completed successfully")
        XCTAssertEqual(decoded.screenshotBase64, "iVBORwkgAAAANSUhEUg==")
        XCTAssertEqual(decoded.axTreeSnapshot, "{\"role\": \"AXWindow\", \"title\": \"Calculator\"}")
    }

    func test_verificationResult_blockedRoundTrip_preservesAllFields() throws {
        let original = VerificationResult(
            state: .blocked,
            reason: "Application crashed unexpectedly",
            screenshotBase64: nil,
            axTreeSnapshot: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerificationResult.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.state, .blocked)
        XCTAssertEqual(decoded.reason, "Application crashed unexpectedly")
        XCTAssertNil(decoded.screenshotBase64)
        XCTAssertNil(decoded.axTreeSnapshot)
    }

    func test_verificationResult_needsClarificationRoundTrip_preservesAllFields() throws {
        let original = VerificationResult(
            state: .needsClarification,
            reason: "Multiple calculators found; which one?",
            screenshotBase64: "abc123",
            axTreeSnapshot: "{\"elements\": []}"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VerificationResult.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.state, .needsClarification)
    }

    // MARK: - P0 Factory Methods (AC3, AC4, AC5)

    func test_verificationResult_doneFactoryMethod_correctState() {
        let result = VerificationResult.done(reason: "Calculator shows 391")
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.reason, "Calculator shows 391")
    }

    func test_verificationResult_blockedFactoryMethod_correctState() {
        let result = VerificationResult.blocked(reason: "Element not found")
        XCTAssertEqual(result.state, .blocked)
        XCTAssertEqual(result.reason, "Element not found")
    }

    func test_verificationResult_needsClarificationFactoryMethod_correctState() {
        let result = VerificationResult.needsClarification(reason: "Ambiguous target")
        XCTAssertEqual(result.state, .needsClarification)
        XCTAssertEqual(result.reason, "Ambiguous target")
    }

    // MARK: - P1 Optional Fields

    func test_verificationResult_done_withoutOptionals() {
        let result = VerificationResult.done()
        XCTAssertEqual(result.state, .done)
        XCTAssertNil(result.reason)
    }

    // MARK: - P1 Equality

    func test_verificationResult_equality_sameValues() {
        let a = VerificationResult(state: .done, reason: "ok", screenshotBase64: nil, axTreeSnapshot: nil)
        let b = VerificationResult(state: .done, reason: "ok", screenshotBase64: nil, axTreeSnapshot: nil)
        XCTAssertEqual(a, b)
    }

    func test_verificationResult_equality_differentReason() {
        let a = VerificationResult(state: .done, reason: "ok", screenshotBase64: nil, axTreeSnapshot: nil)
        let b = VerificationResult(state: .done, reason: "different", screenshotBase64: nil, axTreeSnapshot: nil)
        XCTAssertNotEqual(a, b)
    }
}
