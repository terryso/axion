import Testing
import Foundation
@testable import AxionCore

@Suite("AxionRunResult")
struct AxionRunResultTests {

    @Test("Construction with all fields")
    func construction() {
        let date = Date()
        let result = AxionRunResult(
            sessionId: "20260527-abc123",
            task: "open Safari",
            state: .completed,
            totalSteps: 5,
            durationMs: 3200,
            runSucceeded: true,
            createdAt: date
        )
        #expect(result.sessionId == "20260527-abc123")
        #expect(result.task == "open Safari")
        #expect(result.state == .completed)
        #expect(result.totalSteps == 5)
        #expect(result.durationMs == 3200)
        #expect(result.runSucceeded == true)
        #expect(result.errorMessage == nil)
        #expect(result.createdAt == date)
    }

    @Test("errorMessage is populated for failed results")
    func errorMessageOnFailure() {
        let date = Date()
        let result = AxionRunResult(
            sessionId: "20260527-err",
            task: "fail task",
            state: .failed,
            totalSteps: 0,
            durationMs: 0,
            runSucceeded: false,
            errorMessage: "Something went wrong",
            createdAt: date
        )
        #expect(result.errorMessage == "Something went wrong")
        #expect(result.state == .failed)
    }

    @Test("errorMessage defaults to nil")
    func errorMessageDefaultsNil() {
        let date = Date()
        let result = AxionRunResult(
            sessionId: "id1", task: "t", state: .completed,
            totalSteps: 1, durationMs: 100, runSucceeded: true, createdAt: date
        )
        #expect(result.errorMessage == nil)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = AxionRunResult(
            sessionId: "20260527-xyz789",
            task: "send email",
            state: .failed,
            totalSteps: 0,
            durationMs: 0,
            runSucceeded: false,
            createdAt: date
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AxionRunResult.self, from: data)
        #expect(decoded == original)
    }

    @Test("Equality")
    func equality() {
        let date = Date()
        let a = AxionRunResult(
            sessionId: "id1", task: "t", state: .completed,
            totalSteps: 1, durationMs: 100, runSucceeded: true, createdAt: date
        )
        let b = AxionRunResult(
            sessionId: "id1", task: "t", state: .completed,
            totalSteps: 1, durationMs: 100, runSucceeded: true, createdAt: date
        )
        #expect(a == b)
    }

    @Test("Inequality — different sessionId")
    func inequalitySessionId() {
        let date = Date()
        let a = AxionRunResult(
            sessionId: "id1", task: "t", state: .completed,
            totalSteps: 1, durationMs: 100, runSucceeded: true, createdAt: date
        )
        let b = AxionRunResult(
            sessionId: "id2", task: "t", state: .completed,
            totalSteps: 1, durationMs: 100, runSucceeded: true, createdAt: date
        )
        #expect(a != b)
    }
}
