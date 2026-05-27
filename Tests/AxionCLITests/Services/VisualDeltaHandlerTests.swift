import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("VisualDeltaHandler")
struct VisualDeltaHandlerTests {

    private func makeContext() -> EventHandlerContext {
        EventHandlerContext(
            sessionId: nil,
            config: AxionConfig(apiKey: ""),
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: nil,
            sessionStore: SessionStore(sessionsDir: nil)
        )
    }

    @Test("identifier is 'visual-delta'")
    func testIdentifier() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let id = await handler.identifier
        #expect(id == "visual-delta")
    }

    @Test("subscribed to ToolCompletedEvent")
    func testSubscribedEventTypes() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == ToolCompletedEvent.self })
    }

    @Test("processes screenshot tool events correctly")
    func testProcessesScreenshotEvent() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let context = makeContext()
        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "screenshot",
            durationMs: 100,
            isError: false,
            output: "aGVsbG8=" // valid base64, not a real image
        )
        await handler.handle(event, context: context)
    }

    @Test("ignores non-screenshot tool events")
    func testIgnoresNonScreenshotTools() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let context = makeContext()
        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "click",
            durationMs: 50,
            isError: false,
            output: "done"
        )
        // Should not crash or process
        await handler.handle(event, context: context)
    }

    @Test("does nothing when noVisualDelta is true")
    func testNoVisualDelta() async {
        let handler = VisualDeltaHandler(noVisualDelta: true)
        let context = makeContext()
        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "screenshot",
            durationMs: 100,
            isError: false,
            output: "aGVsbG8="
        )
        // Should not crash — tracker is nil, early return
        await handler.handle(event, context: context)
    }

    @Test("skips when event isError is true")
    func testSkipsErrorEvents() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let context = makeContext()
        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "screenshot",
            durationMs: 100,
            isError: true,
            output: "error message"
        )
        // Should not crash — isError guard returns early
        await handler.handle(event, context: context)
    }

    @Test("skips when output is nil")
    func testSkipsNilOutput() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let context = makeContext()
        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "screenshot",
            durationMs: 100,
            isError: false,
            output: nil
        )
        await handler.handle(event, context: context)
    }

    @Test("handles screenshot tool with compound name")
    func testCompoundToolName() async {
        let handler = VisualDeltaHandler(noVisualDelta: false)
        let context = makeContext()
        let event = ToolCompletedEvent(
            sessionId: "s1",
            toolUseId: "tu1",
            toolName: "take_screenshot",
            durationMs: 100,
            isError: false,
            output: "aGVsbG8="
        )
        await handler.handle(event, context: context)
    }
}
