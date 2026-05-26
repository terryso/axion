import Testing
import Foundation
@testable import AxionCore

@Suite("AxionRunState")
struct AxionRunStateTests {

    // MARK: - Valid transitions

    @Test("CREATED → RUNNING is valid")
    func createdToRunning() {
        #expect(AxionRunState.created.isValidTransition(to: .running))
    }

    @Test("RUNNING → COMPLETED is valid")
    func runningToCompleted() {
        #expect(AxionRunState.running.isValidTransition(to: .completed))
    }

    @Test("RUNNING → FAILED is valid")
    func runningToFailed() {
        #expect(AxionRunState.running.isValidTransition(to: .failed))
    }

    // MARK: - Invalid transitions

    @Test("CREATED → COMPLETED is invalid")
    func createdToCompleted() {
        #expect(!AxionRunState.created.isValidTransition(to: .completed))
    }

    @Test("CREATED → FAILED is invalid")
    func createdToFailed() {
        #expect(!AxionRunState.created.isValidTransition(to: .failed))
    }

    @Test("COMPLETED → RUNNING is invalid")
    func completedToRunning() {
        #expect(!AxionRunState.completed.isValidTransition(to: .running))
    }

    @Test("FAILED → RUNNING is invalid")
    func failedToRunning() {
        #expect(!AxionRunState.failed.isValidTransition(to: .running))
    }

    @Test("RUNNING → CREATED is invalid")
    func runningToCreated() {
        #expect(!AxionRunState.running.isValidTransition(to: .created))
    }

    @Test("COMPLETED → FAILED is invalid")
    func completedToFailed() {
        #expect(!AxionRunState.completed.isValidTransition(to: .failed))
    }

    @Test("FAILED → COMPLETED is invalid")
    func failedToCompleted() {
        #expect(!AxionRunState.failed.isValidTransition(to: .completed))
    }

    @Test("Same-state transitions are invalid")
    func sameStateTransitions() {
        #expect(!AxionRunState.created.isValidTransition(to: .created))
        #expect(!AxionRunState.running.isValidTransition(to: .running))
        #expect(!AxionRunState.completed.isValidTransition(to: .completed))
        #expect(!AxionRunState.failed.isValidTransition(to: .failed))
    }

    // MARK: - Conformance

    @Test("AxionRunState is Codable")
    func codable() throws {
        let original = AxionRunState.running
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AxionRunState.self, from: data)
        #expect(decoded == original)
    }

    @Test("AxionRunState raw values")
    func rawValues() {
        #expect(AxionRunState.created.rawValue == "created")
        #expect(AxionRunState.running.rawValue == "running")
        #expect(AxionRunState.completed.rawValue == "completed")
        #expect(AxionRunState.failed.rawValue == "failed")
    }
}
