import Testing
import Foundation
@testable import AxionCLI

@Suite("SSEEvent")
struct SSEEventTests {

    @Test("StepStartedData codable round trip preserves all fields")
    func stepStartedDataCodableRoundTripPreservesAllFields() throws {
        let data = StepStartedData(stepIndex: 0, tool: "launch_app")

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(StepStartedData.self, from: encoded)

        #expect(decoded.stepIndex == 0)
        #expect(decoded.tool == "launch_app")
    }

    @Test("StepStartedData JSON keys are snake case")
    func stepStartedDataJsonKeysAreSnakeCase() throws {
        let data = StepStartedData(stepIndex: 2, tool: "click")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("\"step_index\""))
        #expect(json.contains("\"tool\""))
    }

    @Test("StepCompletedData codable round trip preserves all fields")
    func stepCompletedDataCodableRoundTripPreservesAllFields() throws {
        let data = StepCompletedData(
            stepIndex: 0,
            tool: "launch_app",
            purpose: "Launch Calculator",
            success: true,
            durationMs: 150
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(StepCompletedData.self, from: encoded)

        #expect(decoded.stepIndex == 0)
        #expect(decoded.tool == "launch_app")
        #expect(decoded.purpose == "Launch Calculator")
        #expect(decoded.success == true)
        #expect(decoded.durationMs == 150)
    }

    @Test("StepCompletedData optional durationMs defaults to nil")
    func stepCompletedDataOptionalDurationMsDefaultsToNil() throws {
        let data = StepCompletedData(
            stepIndex: 1,
            tool: "click",
            purpose: "Click button",
            success: false,
            durationMs: nil
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(StepCompletedData.self, from: encoded)

        #expect(decoded.durationMs == nil)
    }

    @Test("StepCompletedData JSON keys are snake case")
    func stepCompletedDataJsonKeysAreSnakeCase() throws {
        let data = StepCompletedData(
            stepIndex: 1,
            tool: "click",
            purpose: "Input expression",
            success: true,
            durationMs: 200
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("\"step_index\""))
        #expect(json.contains("\"duration_ms\""))
    }

    @Test("RunCompletedData codable round trip preserves all fields")
    func runCompletedDataCodableRoundTripPreservesAllFields() throws {
        let data = RunCompletedData(
            runId: "20260513-abc123",
            finalStatus: "done",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(RunCompletedData.self, from: encoded)

        #expect(decoded.runId == "20260513-abc123")
        #expect(decoded.finalStatus == "done")
        #expect(decoded.totalSteps == 3)
        #expect(decoded.durationMs == 8200)
        #expect(decoded.replanCount == 0)
    }

    @Test("RunCompletedData optional durationMs defaults to nil")
    func runCompletedDataOptionalDurationMsDefaultsToNil() throws {
        let data = RunCompletedData(
            runId: "20260513-xyz789",
            finalStatus: "failed",
            totalSteps: 1,
            durationMs: nil,
            replanCount: 0
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(RunCompletedData.self, from: encoded)

        #expect(decoded.durationMs == nil)
    }

    @Test("RunCompletedData JSON keys are snake case")
    func runCompletedDataJsonKeysAreSnakeCase() throws {
        let data = RunCompletedData(
            runId: "20260513-abc123",
            finalStatus: "done",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("\"run_id\""))
        #expect(json.contains("\"final_status\""))
        #expect(json.contains("\"total_steps\""))
        #expect(json.contains("\"duration_ms\""))
        #expect(json.contains("\"replan_count\""))
    }

    @Test("SSEEvent stepStarted encodes correctly")
    func sseEventStepStartedEncodesCorrectly() throws {
        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))

        let sseString = try event.encodeToSSE(sequenceId: 1)

        #expect(sseString.hasPrefix("event: step_started\n"))
        #expect(sseString.contains("data: "))
        #expect(sseString.contains("id: 1\n"))
        #expect(sseString.hasSuffix("\n\n"))
    }

    @Test("SSEEvent stepCompleted encodes correctly")
    func sseEventStepCompletedEncodesCorrectly() throws {
        let event = SSEEvent.stepCompleted(StepCompletedData(
            stepIndex: 0,
            tool: "launch_app",
            purpose: "Launch Calculator",
            success: true,
            durationMs: 150
        ))

        let sseString = try event.encodeToSSE(sequenceId: 2)

        #expect(sseString.hasPrefix("event: step_completed\n"))
        #expect(sseString.contains("id: 2\n"))
    }

    @Test("SSEEvent runCompleted encodes correctly")
    func sseEventRunCompletedEncodesCorrectly() throws {
        let event = SSEEvent.runCompleted(RunCompletedData(
            runId: "20260513-abc123",
            finalStatus: "done",
            totalSteps: 3,
            durationMs: 8200,
            replanCount: 0
        ))

        let sseString = try event.encodeToSSE(sequenceId: 3)

        #expect(sseString.hasPrefix("event: run_completed\n"))
        #expect(sseString.contains("id: 3\n"))
    }

    @Test("SSEEvent data field contains valid JSON")
    func sseEventDataFieldContainsValidJson() throws {
        let event = SSEEvent.stepStarted(StepStartedData(stepIndex: 0, tool: "launch_app"))
        let sseString = try event.encodeToSSE(sequenceId: 1)

        let lines = sseString.components(separatedBy: "\n")
        let dataLine = try #require(lines.first { $0.hasPrefix("data: ") })
        let jsonSubstring = String(dataLine.dropFirst(6))

        let jsonData = try #require(jsonSubstring.data(using: .utf8))
        _ = try JSONSerialization.jsonObject(with: jsonData)
    }
}
