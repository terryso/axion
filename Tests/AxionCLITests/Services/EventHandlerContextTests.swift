import Testing
import Foundation
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("EventHandlerContext")
struct EventHandlerContextTests {

    private var testConfig: AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    @Test("EventHandlerContext construction with all fields (AC #3)")
    func construction() async {
        let bus = EventBus()
        let store = SessionStore(sessionsDir: NSTemporaryDirectory())
        let takeover = RunMemoryProcessor.TakeoverEventContext(
            issue: "user paused",
            summary: "manual edit done",
            feedback: "looks good",
            reason: "user intervention",
            duration: 5.0
        )

        let context = EventHandlerContext(
            sessionId: "test-session-123",
            config: testConfig,
            eventBus: bus,
            externallyModified: true,
            externallyModifiedFlag: nil,
            takeoverEvent: takeover,
            runCompleteContext: nil,
            sessionStore: store
        )

        #expect(context.sessionId == "test-session-123")
        #expect(context.externallyModified == true)
        #expect(context.takeoverEvent != nil)
        #expect(context.takeoverEvent?.issue == "user paused")
        #expect(context.takeoverEvent?.summary == "manual edit done")
        #expect(context.takeoverEvent?.feedback == "looks good")
        #expect(context.takeoverEvent?.reason == "user intervention")
        #expect(context.takeoverEvent?.duration == 5.0)
        #expect(context.runCompleteContext == nil)
    }

    @Test("EventHandlerContext with nil optional fields")
    func nilOptionals() async {
        let store = SessionStore(sessionsDir: NSTemporaryDirectory())
        let context = EventHandlerContext(
            sessionId: nil,
            config: testConfig,
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: nil,
            sessionStore: store
        )

        #expect(context.sessionId == nil)
        #expect(context.eventBus == nil)
        #expect(context.externallyModified == false)
        #expect(context.takeoverEvent == nil)
    }
}
