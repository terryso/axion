import Foundation
import Testing
@testable import AxionCore

@Suite("RunContext")
struct RunContextTests {

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

    @Test("init with all fields")
    func initWithAllFields() {
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
        #expect(context.planId == planId)
        #expect(context.currentState == .planning)
        #expect(context.currentStepIndex == 0)
        #expect(context.executedSteps.isEmpty)
        #expect(context.replanCount == 0)
        #expect(context.config.apiKey == "test-key")
    }

    // MARK: - Mutation

    @Test("mutate step index")
    func mutateStepIndex() {
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
        #expect(mutable.currentStepIndex == 5)
    }

    @Test("mutate state")
    func mutateState() {
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
        #expect(mutable.currentState == .executing)
    }

    @Test("mutate replan count")
    func mutateReplanCount() {
        var context = RunContext(
            planId: makePlanId(),
            currentState: .replanning,
            currentStepIndex: 0,
            executedSteps: [],
            replanCount: 0,
            config: .default
        )
        context.replanCount = 1
        #expect(context.replanCount == 1)
    }

    @Test("append executed steps")
    func appendExecutedSteps() {
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
        #expect(context.executedSteps.count == 1)
        #expect(context.executedSteps[0].stepIndex == 0)
    }

    @Test("state transitions")
    func stateTransitions() {
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

        #expect(context.currentState == .done)
        #expect(context.currentStepIndex == 1)
        #expect(context.executedSteps.count == 1)
    }

    // MARK: - Codable

    @Test("round trip")
    func roundTrip() throws {
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

        #expect(decoded.planId == planId)
        #expect(decoded.currentState == .executing)
        #expect(decoded.currentStepIndex == 2)
        #expect(decoded.executedSteps.count == 2)
        #expect(decoded.replanCount == 1)
        #expect(decoded.config.apiKey == "sk-test")
        #expect(decoded.config.maxSteps == 10)
    }

    @Test("equality")
    func equality() {
        let planId = makePlanId()
        let a = RunContext(
            planId: planId, currentState: .planning,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        let b = RunContext(
            planId: planId, currentState: .planning,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        #expect(a == b)
    }

    @Test("inequality different state")
    func inequalityDifferentState() {
        let planId = makePlanId()
        let a = RunContext(
            planId: planId, currentState: .planning,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        let b = RunContext(
            planId: planId, currentState: .executing,
            currentStepIndex: 0, executedSteps: [], replanCount: 0, config: .default
        )
        #expect(a != b)
    }
}
