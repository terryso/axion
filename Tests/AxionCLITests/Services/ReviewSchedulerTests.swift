import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Mock ReviewOrchestrator

struct MockReviewOrchestrator: ReviewOrchestrating, Sendable {
    var shouldReviewResult: (memory: Bool, skill: Bool) = (false, false)
    var reviewResult: ReviewAgentResult? = nil
    let callTracker = MockCallTracker()

    func shouldReview(sessionId: String, messageCount: Int, config: ReviewAgentConfig) -> (memory: Bool, skill: Bool) {
        shouldReviewResult
    }

    func executeReview(parentAgent: Agent, messages: [SDKMessage], config: ReviewAgentConfig) async -> ReviewAgentResult? {
        callTracker.recordExecution()
        return reviewResult
    }
}

final class MockCallTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _executeReviewCalled = false

    var executeReviewCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _executeReviewCalled
    }

    func recordExecution() {
        lock.lock()
        _executeReviewCalled = true
        lock.unlock()
    }
}

// MARK: - Tests

@Suite("ReviewScheduler")
struct ReviewSchedulerTests {

    private func makeContext(
        sessionId: String = "test-session",
        runCompleteContext: RunCompleteContext? = nil
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: sessionId,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: runCompleteContext,
            sessionStore: SessionStore(sessionsDir: nil)
        )
    }

    private func makeRunCompleteContext(numTurns: Int = 8) -> RunCompleteContext {
        RunCompleteContext(
            toolPairs: [],
            task: "test task",
            runId: "run-1",
            status: .success,
            usage: TokenUsage(inputTokens: 100, outputTokens: 50),
            totalCostUsd: 0.01,
            durationMs: 1000,
            numTurns: numTurns,
            costBreakdown: []
        )
    }

    private func makeCompletedEvent() -> AgentCompletedEvent {
        AgentCompletedEvent(sessionId: "s1", totalSteps: 5, durationMs: 1000, resultText: "done")
    }

    // MARK: - Task 4.1: shouldReview conditions

    @Test("nil orchestrator in context causes early return without crash")
    func testNilOrchestratorCausesEarlyReturn() async {
        let reviewDataContext = ReviewDataContext()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        // No orchestrator in context → early return (no crash)
        await scheduler.handle(event, context: context)
    }

    // MARK: - Task 4.2: handle() triggers detached Task

    @Test("handle() triggers review when conditions met")
    func testHandleTriggersReview() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["created memory entry"],
                skillChanges: [],
                summary: "Review: 1 memory action",
                reviewMessages: []
            )
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [.userMessage(.init(message: "test"))],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace-\(UUID().uuidString)"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        // Give detached task time to complete
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        #expect(mockOrchestrator.callTracker.executeReviewCalled)
    }

    // MARK: - Task 4.3: lastReviewAt state update

    @Test("lastReviewAt is nil before any review")
    func testLastReviewAtInitiallyNil() async {
        let reviewDataContext = ReviewDataContext()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )
        #expect(scheduler.lastReviewAtValue == nil)
    }

    @Test("lastReviewAt is set after review triggers")
    func testLastReviewAtSetAfterReview() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["created memory"],
                skillChanges: [],
                summary: "Review done",
                reviewMessages: []
            )
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [.userMessage(.init(message: "test"))],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace-\(UUID().uuidString)"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        #expect(scheduler.lastReviewAtValue != nil)
    }

    // MARK: - Task 4.4: noReview/noMemory scenarios

    @Test("noReview=true does not trigger review")
    func testNoReviewBlocksReview() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: true),
            reviewResult: nil
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: true,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        #expect(!mockOrchestrator.callTracker.executeReviewCalled)
    }

    @Test("noMemory=true does not trigger review")
    func testNoMemoryBlocksReview() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: true),
            reviewResult: nil
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: true,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        #expect(!mockOrchestrator.callTracker.executeReviewCalled)
    }

    @Test("ignores non-CompletedEvent events")
    func testIgnoresNonCompletedEvents() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: true),
            reviewResult: nil
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentFailedEvent(sessionId: "s1", error: "boom", stepsCompleted: 2)

        await scheduler.handle(event, context: context)

        #expect(!mockOrchestrator.callTracker.executeReviewCalled)
    }

    // MARK: - Task 4.5: config passing

    @Test("identifier is 'review-scheduler'")
    func testIdentifier() async {
        let reviewDataContext = ReviewDataContext()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )
        let id = await scheduler.identifier
        #expect(id == "review-scheduler")
    }

    @Test("subscribed to AgentCompletedEvent")
    func testSubscribedEventTypes() async {
        let reviewDataContext = ReviewDataContext()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )
        let types = await scheduler.subscribedEventTypes
        #expect(types.contains { $0 == AgentCompletedEvent.self })
    }

    @Test("nil orchestrator in context skips review")
    func testNilOrchestratorSkips() async {
        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(agent: placeholderAgent, messages: [], reviewOrchestrator: nil)

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)
    }

    @Test("nil agent in context skips review")
    func testNilAgentSkips() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: true),
            reviewResult: nil
        )

        // Orchestrator set on one context, but scheduler uses a different one with no agent
        let otherContext = ReviewDataContext()
        otherContext.update(
            agent: Agent(options: AgentOptions(model: "placeholder")),
            messages: [],
            reviewOrchestrator: mockOrchestrator
        )

        // Scheduler reads from empty context — no agent
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: ReviewDataContext(),
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(!mockOrchestrator.callTracker.executeReviewCalled)
    }

    @Test("shouldReview returning false does not trigger review")
    func testShouldReviewFalseSkips() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: false, skill: false),
            reviewResult: nil
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace"
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 3))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(!mockOrchestrator.callTracker.executeReviewCalled)
    }
}
