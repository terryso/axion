import Foundation
import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

final class NotificationCapture: @unchecked Sendable {
    var title: String?
    var subtitle: String?
    var message: String?
    var callCount = 0
}

@Suite("NotificationHandler")
struct NotificationHandlerTests {

    private func makeContext(
        runCompleteContext: RunCompleteContext? = nil
    ) -> EventHandlerContext {
        EventHandlerContext(
            sessionId: nil,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: runCompleteContext,
            sessionStore: SessionStore(sessionsDir: nil)
        )
    }

    private func makeRunCompleteContext() -> RunCompleteContext {
        RunCompleteContext(
            toolPairs: [],
            task: "test task",
            runId: "run-1",
            status: .success,
            usage: TokenUsage(inputTokens: 100, outputTokens: 50),
            totalCostUsd: 0.05,
            durationMs: 5000,
            numTurns: 3,
            costBreakdown: []
        )
    }

    @Test("identifier is 'notification'")
    func testIdentifier() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let id = await handler.identifier
        #expect(id == "notification")
    }

    @Test("subscribed to terminal events")
    func testSubscribedEventTypes() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == AgentCompletedEvent.self })
        #expect(types.contains { $0 == AgentFailedEvent.self })
        #expect(types.contains { $0 == AgentInterruptedEvent.self })
    }

    @Test("handler with json=true skips")
    func testJsonModeSkips() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: true) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 3, durationMs: 5000, resultText: "done"
        )
        await handler.handle(event, context: context)
        #expect(capture.callCount == 0)
    }

    @Test("handler sends notification on AgentCompletedEvent without runCompleteContext")
    func testSendsNotificationWithoutRunCompleteContext() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let context = makeContext(runCompleteContext: nil)
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 3, durationMs: 5000, resultText: "done"
        )
        await handler.handle(event, context: context)

        #expect(capture.callCount == 1)
        #expect(capture.title == "Axion 完成")
        #expect(capture.subtitle == "耗时 5s · $0.00")
        #expect(capture.message == "done")
    }

    @Test("handler sends notification on AgentCompletedEvent with cost")
    func testSendsNotificationOnCompleted() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let context = makeContext(runCompleteContext: makeRunCompleteContext())
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 3, durationMs: 5000, resultText: "done"
        )
        await handler.handle(event, context: context)

        #expect(capture.callCount == 1)
        #expect(capture.title == "Axion 完成")
        #expect(capture.subtitle == "耗时 5s · $0.05")
    }

    @Test("handler sends notification on AgentFailedEvent")
    func testSendsNotificationOnFailed() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let context = makeContext(runCompleteContext: nil)
        let event = AgentFailedEvent(
            sessionId: "s1", error: "something went wrong", stepsCompleted: 2
        )
        await handler.handle(event, context: context)

        #expect(capture.callCount == 1)
        #expect(capture.title == "Axion 失败")
        #expect(capture.message == "something went wrong")
    }

    @Test("handler handles AgentInterruptedEvent")
    func testSendsNotificationOnInterrupted() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        let context = makeContext(runCompleteContext: nil)
        let event = AgentInterruptedEvent(sessionId: "s1", stepsCompleted: 1)
        await handler.handle(event, context: context)

        #expect(capture.callCount == 1)
        #expect(capture.title == "Axion 已取消")
    }

    @Test("handler uses resultText fallback chain for completed event")
    func testResultTextFallback() async {
        let capture = NotificationCapture()
        let handler = NotificationHandler(json: false) { title, subtitle, message in
            capture.title = title
            capture.subtitle = subtitle
            capture.message = message
            capture.callCount += 1
        }
        // context.sessionId is nil, resultText is nil → fallback to "任务完成"
        let context = makeContext(runCompleteContext: nil)
        let event = AgentCompletedEvent(
            sessionId: "s1", totalSteps: 1, durationMs: 1000, resultText: nil
        )
        await handler.handle(event, context: context)

        #expect(capture.callCount == 1)
        #expect(capture.message == "任务完成")
    }
}
