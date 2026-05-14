import Testing
import Foundation
@testable import AxionBar

@MainActor
@Suite("SSEEventClient")
struct SSEEventClientTests {

    @Test("default initialization succeeds")
    func defaultInit() {
        let client = SSEEventClient()
        #expect(client != nil)
    }

    @Test("custom baseURL initialization succeeds")
    func customBaseURLInit() {
        let client = SSEEventClient(baseURL: "http://localhost:9999")
        #expect(client != nil)
    }

    @Test("connect with invalid URL returns empty stream")
    func connectInvalidURL() async {
        let client = SSEEventClient(baseURL: "http://127.0.0.1:19999")
        let stream = client.connect(runId: "test-run")

        var events: [BarSSEEvent] = []
        for await event in stream {
            events.append(event)
            if events.count > 5 { break }
        }
        #expect(events.isEmpty)
    }

    @Test("disconnect cancels active connection")
    func disconnectCancels() {
        let client = SSEEventClient()
        let _ = client.connect(runId: "test")
        client.disconnect()
    }
}

@MainActor
@Suite("SSEEventClient Parsing")
struct SSEEventClientParsingTests {

    @Test("parseSSEEvent decodes step_started")
    func parseStepStarted() {
        let client = SSEEventClient()
        let result = client.parseSSEEvent(
            eventType: "step_started",
            dataString: #"{"step_index":0,"tool":"launch_app"}"#
        )
        #expect(result != nil)
        if case .stepStarted(let data) = result {
            #expect(data.stepIndex == 0)
            #expect(data.tool == "launch_app")
        } else {
            #expect(Bool(false), "Expected stepStarted event")
        }
    }

    @Test("parseSSEEvent decodes step_completed")
    func parseStepCompleted() {
        let client = SSEEventClient()
        let result = client.parseSSEEvent(
            eventType: "step_completed",
            dataString: #"{"step_index":0,"tool":"click","purpose":"点击按钮","success":true,"duration_ms":150}"#
        )
        #expect(result != nil)
        if case .stepCompleted(let data) = result {
            #expect(data.success == true)
            #expect(data.durationMs == 150)
        } else {
            #expect(Bool(false), "Expected stepCompleted event")
        }
    }

    @Test("parseSSEEvent decodes run_completed")
    func parseRunCompleted() {
        let client = SSEEventClient()
        let result = client.parseSSEEvent(
            eventType: "run_completed",
            dataString: #"{"run_id":"20260515-abc","final_status":"done","total_steps":3,"duration_ms":5000,"replan_count":0}"#
        )
        #expect(result != nil)
        if case .runCompleted(let data) = result {
            #expect(data.finalStatus == "done")
            #expect(data.totalSteps == 3)
        } else {
            #expect(Bool(false), "Expected runCompleted event")
        }
    }

    @Test("parseSSEEvent returns nil for unknown event type")
    func parseUnknownEvent() {
        let client = SSEEventClient()
        let result = client.parseSSEEvent(
            eventType: "unknown_event",
            dataString: #"{}"#
        )
        #expect(result == nil)
    }

    @Test("parseSSEEvent returns nil for invalid JSON")
    func parseInvalidJSON() {
        let client = SSEEventClient()
        let result = client.parseSSEEvent(
            eventType: "step_started",
            dataString: "not valid json"
        )
        #expect(result == nil)
    }
}
