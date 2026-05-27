import Testing
import OpenAgentSDK
@testable import AxionCLI
@testable import AxionCore

@Suite("SeatMonitorHandler")
struct SeatMonitorHandlerTests {

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

    @Test("identifier is 'seat-monitor'")
    func testIdentifier() async {
        let handler = SeatMonitorHandler(sharedSeatMode: true)
        let id = await handler.identifier
        #expect(id == "seat-monitor")
    }

    @Test("subscribed to ToolStartedEvent")
    func testSubscribedEventTypes() async {
        let handler = SeatMonitorHandler(sharedSeatMode: true)
        let types = await handler.subscribedEventTypes
        #expect(types.contains { $0 == ToolStartedEvent.self })
    }

    @Test("handler with sharedSeatMode=false does nothing")
    func testDisabledMode() async {
        let handler = SeatMonitorHandler(sharedSeatMode: false)
        let context = makeContext()
        let event = ToolStartedEvent(
            sessionId: "s1",
            toolName: "mcp__axion-helper__click",
            toolUseId: "tu1",
            input: nil
        )
        await handler.handle(event, context: context)
    }

    @Test("handler ignores non-helper tool events")
    func testIgnoresNonHelperTools() async {
        let handler = SeatMonitorHandler(sharedSeatMode: true)
        let context = makeContext()
        let event = ToolStartedEvent(
            sessionId: "s1",
            toolName: "bash",
            toolUseId: "tu1",
            input: nil
        )
        await handler.handle(event, context: context)
    }

    @Test("handler processes helper tool events")
    func testProcessesHelperToolEvents() async {
        let handler = SeatMonitorHandler(sharedSeatMode: true)
        let context = makeContext()
        let event = ToolStartedEvent(
            sessionId: "s1",
            toolName: "mcp__axion-helper__click",
            toolUseId: "tu1",
            input: nil
        )
        // SeatActivityMonitor.create() may return nil in CI (no AppKit),
        // but the handler should not crash either way.
        await handler.handle(event, context: context)
    }

    @Test("handler ignores non-ToolStartedEvent types")
    func testIgnoresOtherEventTypes() async {
        let handler = SeatMonitorHandler(sharedSeatMode: true)
        let context = makeContext()
        let event = AgentCompletedEvent(
            sessionId: "s1",
            totalSteps: 5,
            durationMs: 1000,
            resultText: "done"
        )
        await handler.handle(event, context: context)
    }
}
