import XCTest
@testable import OpenAgentSDK

final class SDKMessageOutputHandlerTests: XCTestCase {
    /// Verifies a mock struct can implement the protocol — compile-time proof.
    func testMockHandlerConformsToProtocol() {
        let handler = MockOutputHandler()
        let existential: any SDKMessageOutputHandler = handler

        existential.displayRunStart(runId: "r1", task: "test")
        existential.handle(.result(.init(subtype: .success, text: "ok", usage: nil, numTurns: 1, durationMs: 100)))
        existential.displayCompletion()

        XCTAssertEqual(handler.calls, [
            "displayRunStart(r1, test)",
            "handle",
            "displayCompletion",
        ])
    }

    func testProtocolMethodsCallableThroughExistential() {
        let handler = MockOutputHandler()
        let existential: any SDKMessageOutputHandler = handler

        existential.displayRunStart(runId: "run-x", task: "task-y")
        existential.handle(.toolUse(.init(toolName: "Read", toolUseId: "tu-1", input: "{}")))
        existential.displayCompletion()

        XCTAssertEqual(handler.calls.count, 3)
    }
}

/// A mock handler proving the protocol is implementable by a concrete struct.
private struct MockOutputHandler: SDKMessageOutputHandler, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        var calls: [String] = []
    }

    private let state = State()

    var calls: [String] { state.calls }

    func displayRunStart(runId: String, task: String) {
        state.calls.append("displayRunStart(\(runId), \(task))")
    }

    func handle(_ message: SDKMessage) {
        state.calls.append("handle")
    }

    func displayCompletion() {
        state.calls.append("displayCompletion")
    }
}
