import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

// MARK: - Mock ReviewOrchestrator

/// Thread-safe box for capturing a single optional ReviewResultEvent in tests.
final class ReviewEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: ReviewResultEvent?
    private let _signal = DispatchSemaphore(value: 0)

    var value: ReviewResultEvent? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ newValue: ReviewResultEvent) {
        lock.lock()
        _value = newValue
        lock.unlock()
        _signal.signal()
    }

    /// Block until `set()` is called or timeout expires.
    func wait(timeout: TimeInterval) -> ReviewResultEvent? {
        let result = _signal.wait(timeout: .now() + timeout)
        return result == .success ? value : nil
    }
}

struct MockReviewOrchestrator: ReviewOrchestrating, Sendable {
    var shouldReviewResult: (memory: Bool, skill: Bool) = (false, false)
    var reviewResult: ReviewAgentResult? = nil
    let callTracker = MockCallTracker()

    func shouldReview(sessionId: String, messageCount: Int, config: ReviewAgentConfig) -> (memory: Bool, skill: Bool) {
        callTracker.recordShouldReview(config: config)
        return shouldReviewResult
    }

    func executeReview(parentAgent: Agent, messages: [SDKMessage], config: ReviewAgentConfig) async -> ReviewAgentResult? {
        callTracker.recordExecution()
        callTracker.recordExecuteReview(config: config)
        return reviewResult
    }
}

final class MockCallTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _executeReviewCalled = false
    private var _shouldReviewConfig: ReviewAgentConfig?
    private var _executeReviewConfig: ReviewAgentConfig?

    var executeReviewCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _executeReviewCalled
    }

    var shouldReviewConfig: ReviewAgentConfig? {
        lock.lock()
        defer { lock.unlock() }
        return _shouldReviewConfig
    }

    var executeReviewConfig: ReviewAgentConfig? {
        lock.lock()
        defer { lock.unlock() }
        return _executeReviewConfig
    }

    func recordExecution() {
        lock.lock()
        _executeReviewCalled = true
        lock.unlock()
    }

    func recordShouldReview(config: ReviewAgentConfig) {
        lock.lock()
        _shouldReviewConfig = config
        lock.unlock()
    }

    func recordExecuteReview(config: ReviewAgentConfig) {
        lock.lock()
        _executeReviewConfig = config
        lock.unlock()
    }
}

// MARK: - Tests

@Suite("ReviewScheduler")
struct ReviewSchedulerTests {
    private func makeTempDirectory(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeContext(
        sessionId: String = "test-session",
        runCompleteContext: RunCompleteContext? = nil,
        shouldReviewMemory: Bool = true,
        chatId: Int64 = 12345
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: sessionId,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: runCompleteContext,
            sessionStore: SessionStore(sessionsDir: nil),
            chatId: chatId,
            shouldReviewMemory: shouldReviewMemory
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

        // Wait for the detached task to complete
        let deadline = ContinuousClock.now + .seconds(3)
        while !mockOrchestrator.callTracker.executeReviewCalled, ContinuousClock.now < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(mockOrchestrator.callTracker.executeReviewCalled)
    }

    @Test("gateway review path allows universal memory writeback")
    func testGatewayReviewAllowsUniversalMemoryWriteback() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["saved user preference"],
                skillChanges: [],
                summary: "Review: 1 memory action",
                reviewMessages: []
            )
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [.userMessage(.init(message: "以后回答不要加 emoji"))],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace-\(UUID().uuidString)"
        )

        await scheduler.handle(makeCompletedEvent(), context: makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8)))

        let deadline = ContinuousClock.now + .seconds(3)
        while !mockOrchestrator.callTracker.executeReviewCalled, ContinuousClock.now < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(mockOrchestrator.callTracker.executeReviewConfig?.allowedTools.contains("review_save_universal_memory") == true)
    }

    @Test("fallback saves explicit response preference to USER.md when review misses it")
    func testFallbackSavesExplicitResponsePreference() async throws {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: [],
                skillChanges: [],
                summary: "Review completed. No actions taken.",
                reviewMessages: []
            )
        )

        let memoryDir = try makeTempDirectory(prefix: "axion-review-memory")
        defer { try? FileManager.default.removeItem(at: memoryDir) }
        let traceDir = try makeTempDirectory(prefix: "axion-review-trace")
        defer { try? FileManager.default.removeItem(at: traceDir) }

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [.userMessage(.init(message: "以后回答不要加 emoji，并告诉我这个仓库根目录有哪些顶层文件"))],
            reviewOrchestrator: mockOrchestrator
        )

        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: traceDir.path,
            memoryDir: memoryDir.path
        )

        await scheduler.handle(makeCompletedEvent(), context: makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8)))

        let deadline = ContinuousClock.now + .seconds(3)
        let store = UniversalMemoryStore(memoryDir: memoryDir.path)
        var content = await store.read(target: .user)
        while content.isEmpty, ContinuousClock.now < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
            content = await store.read(target: .user)
        }

        #expect(content.contains("以后回答不要加 emoji"))
        // Wait for detached task to update lastReviewSummaryValue
        var summaryValue: String?
        let summaryDeadline = ContinuousClock.now + .seconds(3)
        while summaryValue == nil, ContinuousClock.now < summaryDeadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
            summaryValue = scheduler.lastReviewSummaryValue
        }
        #expect(summaryValue == "新增 1 条记忆")
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

        // Wait for the detached task to set lastReviewAt
        let deadline = ContinuousClock.now + .seconds(3)
        while scheduler.lastReviewAtValue == nil, ContinuousClock.now < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }
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

    @Test("shouldReviewMemory false does not trigger review")
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

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 3), shouldReviewMemory: false)
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(!mockOrchestrator.callTracker.executeReviewCalled)
    }

    // MARK: - Task 2: ReviewResultEvent emission

    @Test("ReviewResultEvent published on successful review")
    func testEventPublishedOnSuccess() async {
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

        let eventBus = EventBus()
        let context = makeContextWithEventBus(eventBus, runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        let eventBox = ReviewEventBox()
        let subscription = await eventBus.subscribe(ReviewResultEvent.self)
        let listenerTask = _Concurrency.Task {
            for await e in subscription {
                eventBox.set(e)
                return
            }
        }

        await scheduler.handle(event, context: context)

        let receivedEvent = eventBox.wait(timeout: 3)
        #expect(receivedEvent != nil)
        #expect(receivedEvent!.success == true)
        #expect(receivedEvent!.summary == "Review done")
        #expect(receivedEvent!.memoryChanges == ["created memory"])
        #expect(receivedEvent!.sessionId == "test-session")

        listenerTask.cancel()
    }

    @Test("ReviewResultEvent published on review failure (nil result)")
    func testEventPublishedOnFailure() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: nil
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

        let eventBus = EventBus()
        let context = makeContextWithEventBus(eventBus, runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        let eventBox = ReviewEventBox()
        let subscription = await eventBus.subscribe(ReviewResultEvent.self)
        let listenerTask = _Concurrency.Task {
            for await e in subscription {
                eventBox.set(e)
                return
            }
        }

        await scheduler.handle(event, context: context)

        let receivedEvent = eventBox.wait(timeout: 3)
        #expect(receivedEvent != nil)
        #expect(receivedEvent!.success == false)
        #expect(receivedEvent!.memoryChanges.isEmpty)

        listenerTask.cancel()
    }

    @Test("No event published when eventBus is nil")
    func testNoEventWhenEventBusNil() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["mem"],
                skillChanges: [],
                summary: "done",
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

        // Should not crash when eventBus is nil
        await scheduler.handle(event, context: context)

        // Wait for the detached task to complete
        let deadline = ContinuousClock.now + .seconds(3)
        while !mockOrchestrator.callTracker.executeReviewCalled, ContinuousClock.now < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(mockOrchestrator.callTracker.executeReviewCalled)
    }

    @Test("lastReviewSummaryValue is set after successful review with changes")
    func testLastReviewSummarySetAfterReview() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: true),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["m1"],
                skillChanges: ["s1"],
                summary: "Full review summary",
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

        #expect(scheduler.lastReviewSummaryValue == nil)

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        // Wait for the detached task to set lastReviewSummary
        let deadline = ContinuousClock.now + .seconds(3)
        while scheduler.lastReviewSummaryValue == nil, ContinuousClock.now < deadline {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }

        let summary = scheduler.lastReviewSummaryValue
        #expect(summary != nil)
        #expect(summary!.contains("1 条记忆"))
        #expect(summary!.contains("1 个技能"))
    }

    // MARK: - onReviewResult callback

    @Test("onReviewResult callback is invoked on successful review")
    func testOnReviewResultCallbackSuccess() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["mem-1"],
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

        let callbackBox = ReviewEventBox()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace-\(UUID().uuidString)",
            onReviewResult: { event in
                callbackBox.set(event)
            }
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        let received = callbackBox.wait(timeout: 3)
        #expect(received != nil)
        #expect(received!.success == true)
        #expect(received!.memoryChanges == ["mem-1"])
        #expect(received!.sessionId == "test-session")
    }

    @Test("onReviewResult callback is invoked on review failure")
    func testOnReviewResultCallbackFailure() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: nil
        )

        let reviewDataContext = ReviewDataContext()
        let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
        reviewDataContext.update(
            agent: placeholderAgent,
            messages: [.userMessage(.init(message: "test"))],
            reviewOrchestrator: mockOrchestrator
        )

        let callbackBox = ReviewEventBox()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace-\(UUID().uuidString)",
            onReviewResult: { event in
                callbackBox.set(event)
            }
        )

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        let received = callbackBox.wait(timeout: 3)
        #expect(received != nil)
        #expect(received!.success == false)
        #expect(received!.memoryChanges.isEmpty)
    }

    @Test("setOnReviewResult updates callback after init")
    func testSetOnReviewResultUpdatesCallback() async {
        let mockOrchestrator = MockReviewOrchestrator(
            shouldReviewResult: (memory: true, skill: false),
            reviewResult: ReviewAgentResult(
                memoryChanges: ["mem"],
                skillChanges: [],
                summary: "done",
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

        let callbackBox = ReviewEventBox()
        let scheduler = ReviewScheduler(
            noReview: false,
            noMemory: false,
            reviewDataContext: reviewDataContext,
            traceDir: "/tmp/test-trace-\(UUID().uuidString)"
        )

        await scheduler.setOnReviewResult { event in
            callbackBox.set(event)
        }

        let context = makeContext(runCompleteContext: makeRunCompleteContext(numTurns: 8))
        let event = makeCompletedEvent()

        await scheduler.handle(event, context: context)

        let callbackResult = callbackBox.wait(timeout: 3)
        #expect(callbackResult != nil)
        #expect(callbackResult!.success == true)
    }

    private func makeContextWithEventBus(
        _ eventBus: EventBus,
        sessionId: String = "test-session",
        runCompleteContext: RunCompleteContext? = nil,
        shouldReviewMemory: Bool = true,
        chatId: Int64 = 12345
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: sessionId,
            config: AxionConfig(apiKey: ""),
            eventBus: eventBus,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: runCompleteContext,
            sessionStore: SessionStore(sessionsDir: nil),
            chatId: chatId,
            shouldReviewMemory: shouldReviewMemory
        )
    }
}
