import Foundation
import XCTest
@testable import AxionCore

final class RunContextTests: XCTestCase {

    private func makePlanId() -> UUID { UUID() }

    private func makeStep(index: Int) -> Step {
        Step(index: index, tool: "click", parameters: ["x": .int(100)], purpose: "Click", expectedChange: "Clicked")
    }

    private func makeExecutedStep(index: Int) -> ExecutedStep {
        ExecutedStep(
            stepIndex: index, tool: "click",
            parameters: ["x": .int(100)],
            result: "ok", success: true,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
    }

    // MARK: - Creation

    func test_init_withAllFields() {
        let planId = makePlanId()
        let config = AxionConfig(apiKey: "test-key", maxSteps: 10)
        let context = RunContext(
            planId: planId,
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: config
        )
        XCTAssertEqual(context.planId, planId)
        XCTAssertEqual(context.currentState, .planning)
        XCTAssertEqual(context.currentStepIndex, 0)
        XCTAssertTrue(context.executedSteps.isEmpty)
        XCTAssertEqual(context.replanCount, 0)
        XCTAssertEqual(context.config.apiKey, "test-key")
    }

    // MARK: - Mutation

    func test_mutateStepIndex() {
        let context = RunContext(
            planId: makePlanId(),
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: .default
        )
        var mutable = context
        mutable.currentStepIndex = 5
        XCTAssertEqual(mutable.currentStepIndex, 5)
    }

    func test_mutateState() {
        let context = RunContext(
            planId: makePlanId(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: .default
        )
        var mutable = context
        mutable.currentState = .executing
        XCTAssertEqual(mutable.currentState, .executing)
    }

    func test_mutateReplanCount() {
        var context = RunContext(
            planId: makePlanId(),
            currentState: .replanning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: .default
        )
        context.replanCount = 1
        XCTAssertEqual(context.replanCount, 1)
    }

    func test_appendExecutedSteps() {
        var context = RunContext(
            planId: makePlanId(),
            currentState: .executing,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: .default
        )
        let step = makeExecutedStep(index: 0)
        context.executedSteps.append(step)
        XCTAssertEqual(context.executedSteps.count, 1)
        XCTAssertEqual(context.executedSteps[0].stepIndex, 0)
    }

    func test_stateTransitions() {
        var context = RunContext(
            planId: makePlanId(),
            currentState: .planning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: .default
        )

        context.currentState = .executing
        context.currentStepIndex = 0
        context.executedSteps.append(makeExecutedStep(index: 0))
        context.currentStepIndex = 1

        context.currentState = .verifying
        context.currentState = .done

        XCTAssertEqual(context.currentState, .done)
        XCTAssertEqual(context.currentStepIndex, 1)
        XCTAssertEqual(context.executedSteps.count, 1)
    }

    // MARK: - Codable

    func test_roundTrip() throws {
        let planId = makePlanId()
        let context = RunContext(
            planId: planId,
            currentState: .executing,
            currentStepIndex: 2,
            executedSteps: [makeExecutedStep(index: 0), makeExecutedStep(index: 1)],
            replanCount: 1,
            config: AxionConfig(apiKey: "sk-test", maxSteps: 10, maxBatches: 3)
        )
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(RunContext.self, from: data)

        XCTAssertEqual(decoded.planId, planId)
        XCTAssertEqual(decoded.currentState, .executing)
        XCTAssertEqual(decoded.currentStepIndex, 2)
        XCTAssertEqual(decoded.executedSteps.count, 2)
        XCTAssertEqual(decoded.replanCount, 1)
        XCTAssertEqual(decoded.config.apiKey, "sk-test")
        XCTAssertEqual(decoded.config.maxSteps, 10)
    }

    func test_equality() {
        let planId = makePlanId()
        let a = RunContext(
            planId: planId, currentState: .planning,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        let b = RunContext(
            planId: planId, currentState: .planning,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        XCTAssertEqual(a, b)
    }

    func test_inequality_differentState() {
        let planId = makePlanId()
        let a = RunContext(
            planId: planId, currentState: .planning,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        let b = RunContext(
            planId: planId, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        XCTAssertNotEqual(a, b)
    }
}
