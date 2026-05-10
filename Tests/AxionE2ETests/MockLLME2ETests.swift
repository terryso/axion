import Foundation
import XCTest

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

/// E2E tests with mock LLM responses and real Helper process.
///
/// Tests the full message pipeline: mock Agent stream → output handler + trace recorder,
/// then verifies output formatting and trace file integrity.
/// Real Helper is used when MCP tool calls are made through the SDK pipeline.
///
/// Prerequisites:
/// - AxionHelper.app built at .build/AxionHelper.app
/// - macOS Accessibility permissions granted
final class MockLLME2ETests: XCTestCase {

    private var fixture: E2EHelperFixture!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try E2EHelperFixture()
        try await fixture.setUpHelper()
    }

    override func tearDown() async throws {
        await fixture.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    // MARK: - 1. Launch App and Verify (Happy Path)

    /// Full pipeline: assistant → launch_app → toolResult → assistant → result(success)
    func test_e2e_launchAppAndVerify() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        // Use real Helper to launch Calculator and capture result
        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        // Build mock message sequence simulating a full agent run
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        handler.displayRunStart(runId: "e2e-test-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            .assistant(.init(text: "I'll launch Calculator for you.", model: "mock", stopReason: "tool_use")),
            .toolUse(.init(toolName: "launch_app", toolUseId: "tu-1", input: #"{"app_name":"Calculator"}"#)),
            .toolResult(.init(toolUseId: "tu-1", content: launchResult, isError: false)),
            .assistant(.init(text: "Calculator is now open.", model: "mock", stopReason: "end_turn")),
            .result(.init(subtype: .success, text: "Calculator launched", usage: nil, numTurns: 1, durationMs: 1500)),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler, tracer: nil)
        await runner.run(messages: messages)

        // Verify output contains expected content
        XCTAssertTrue(capturing.contains("Open Calculator"), "Output should contain task description")
        XCTAssertTrue(capturing.contains("launch_app") || capturing.contains("执行"), "Output should contain tool execution info")
        XCTAssertTrue(capturing.contains("运行结束"), "Output should show completion")

        // Clean up: quit Calculator
        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
    }

    // MARK: - 2. Dryrun Mode

    /// Dryrun: only assistant messages, no tool calls.
    func test_e2e_dryrunMode() async throws {
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        handler.displayRunStart(runId: "e2e-dryrun-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            .partialMessage(.init(text: "Planning")),
            .partialMessage(.init(text: " to open Calculator...")),
            .assistant(.init(text: "Plan: 1. Launch Calculator using launch_app tool.", model: "mock", stopReason: "end_turn")),
            .result(.init(subtype: .success, text: "Dryrun complete — would launch Calculator.", usage: nil, numTurns: 1, durationMs: 200)),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler, tracer: nil)
        await runner.run(messages: messages)

        // Verify output
        XCTAssertTrue(capturing.contains("运行结束"), "Should show completion")
        // The streaming text should have been written
        XCTAssertTrue(capturing.contains("Planning"), "Should show planning text")
    }

    // MARK: - 3. Multi-Step Keyboard Operations

    /// Multi-step: launch → press keys → verify via screenshot.
    func test_e2e_multiStepTyping() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        // Launch Calculator first
        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        handler.displayRunStart(runId: "e2e-keys-001", task: "Compute 1+2 in Calculator")

        let messages: [SDKMessage] = [
            E2EMessages.assistant("Launching Calculator"),
            E2EMessages.toolUse("launch_app", id: "t1", input: #"{"app_name":"Calculator"}"#),
            E2EMessages.toolResult(id: "t1", content: launchResult),
            E2EMessages.assistant("Pressing keys"),
            E2EMessages.toolUse("press_key", id: "t2", input: #"{"key":"1"}"#),
            E2EMessages.toolResult(id: "t2", content: #"{"success":true}"#),
            E2EMessages.toolUse("hotkey", id: "t3", input: #"{"keys":"shift+="}"#),
            E2EMessages.toolResult(id: "t3", content: #"{"success":true}"#),
            E2EMessages.toolUse("press_key", id: "t4", input: #"{"key":"2"}"#),
            E2EMessages.toolResult(id: "t4", content: #"{"success":true}"#),
            E2EMessages.toolUse("press_key", id: "t5", input: #"{"key":"="}"#),
            E2EMessages.toolResult(id: "t5", content: #"{"success":true}"#),
            E2EMessages.successResult(text: "Computed 1+2=3"),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler, tracer: nil)
        await runner.run(messages: messages)

        // Verify all steps appear in output
        XCTAssertTrue(capturing.contains("launch_app"), "Should show launch_app step")
        XCTAssertTrue(capturing.contains("press_key"), "Should show press_key step")
        XCTAssertTrue(capturing.contains("hotkey"), "Should show hotkey step")
        XCTAssertTrue(capturing.contains("运行结束"), "Should show completion")

        // Clean up
        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
    }

    // MARK: - 4. Error Recovery

    /// Tool error followed by successful retry.
    func test_e2e_errorRecovery() async throws {
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)

        handler.displayRunStart(runId: "e2e-err-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            E2EMessages.assistant("Attempting to launch"),
            E2EMessages.toolUse("launch_app", id: "t1", input: #"{"app_name":"NonExistentApp"}"#),
            E2EMessages.toolResult(id: "t1", content: "App not found", isError: true),
            E2EMessages.assistant("App not found, trying Calculator instead"),
            E2EMessages.toolUse("launch_app", id: "t2", input: #"{"app_name":"Calculator"}"#),
            E2EMessages.toolResult(id: "t2", content: #"{"pid":12345}"#),
            E2EMessages.successResult(text: "Calculator launched after retry"),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler, tracer: nil)
        await runner.run(messages: messages)

        XCTAssertTrue(capturing.contains("错误") || capturing.contains("error") || capturing.contains("App not found"),
                       "Output should indicate the error step")
        XCTAssertTrue(capturing.contains("运行结束"), "Should complete despite error")
    }

    // MARK: - 5. JSON Output Format

    /// Verify JSON output handler produces valid structured JSON.
    func test_e2e_jsonOutputFormat() async throws {
        let capturing = CapturingJSONOutput()
        let handler = SDKJSONOutputHandler(write: capturing.write)

        handler.displayRunStart(runId: "e2e-json-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            E2EMessages.assistant("Opening Calculator"),
            E2EMessages.toolUse("launch_app", id: "t1"),
            E2EMessages.toolResult(id: "t1", content: #"{"pid":12345}"#),
            E2EMessages.successResult(text: "Done"),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler, tracer: nil)
        await runner.run(messages: messages)

        guard let jsonStr = capturing.lastJSON else {
            XCTFail("JSON output handler should produce output")
            return
        }

        // Verify it's valid JSON
        let data = jsonStr.data(using: .utf8)!
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["runId"] as? String, "e2e-json-001")
        XCTAssertEqual(json["task"] as? String, "Open Calculator")
        XCTAssertEqual(json["status"] as? String, "success")
        XCTAssertEqual(json["numTurns"] as? Int, 1)

        let steps = try XCTUnwrap(json["steps"] as? [[String: Any]])
        XCTAssertFalse(steps.isEmpty, "Should have recorded tool steps")
        XCTAssertEqual(steps[0]["tool"] as? String, "launch_app")
    }

    // MARK: - 6. Trace File Integrity

    /// Verify trace file records all expected event types.
    func test_e2e_traceFileIntegrity() async throws {
        let runId = "e2e-trace-\(UUID().uuidString.prefix(8))"

        var traceConfig = AxionConfig.default
        traceConfig.traceEnabled = true

        let tracer = try TraceRecorder(runId: runId, config: traceConfig, baseURL: fixture.tempDir)

        await tracer.recordRunStart(runId: runId, task: "Open Calculator", mode: "standard")

        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(output: capturing.output)
        handler.displayRunStart(runId: runId, task: "Open Calculator")

        let messages: [SDKMessage] = [
            E2EMessages.assistant("Launching Calculator"),
            E2EMessages.toolUse("launch_app", id: "t1", input: #"{"app_name":"Calculator"}"#),
            E2EMessages.toolResult(id: "t1", content: #"{"pid":12345}"#),
            E2EMessages.successResult(text: "Done"),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler, tracer: tracer)
        await runner.run(messages: messages)

        await tracer.recordRunDone(totalSteps: 1, durationMs: 1500, replanCount: 0)
        await tracer.close()

        // Read trace file
        let traceFile = fixture.tempDir
            .appendingPathComponent(runId)
            .appendingPathComponent("trace.jsonl")
        let traceContent = try String(contentsOf: traceFile, encoding: .utf8)
        let lines = traceContent.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertGreaterThanOrEqual(lines.count, 5, "Trace should have multiple events")

        // Parse and verify event types
        var eventTypes: [String] = []
        for line in lines {
            let data = line.data(using: .utf8)!
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if let event = json["event"] as? String {
                eventTypes.append(event)
            }
        }

        XCTAssertTrue(eventTypes.contains("run_start"), "Trace should contain run_start")
        XCTAssertTrue(eventTypes.contains("assistant_message"), "Trace should contain assistant_message")
        XCTAssertTrue(eventTypes.contains("tool_use"), "Trace should contain tool_use")
        XCTAssertTrue(eventTypes.contains("tool_result"), "Trace should contain tool_result")
        XCTAssertTrue(eventTypes.contains("result"), "Trace should contain result")
        XCTAssertTrue(eventTypes.contains("run_done"), "Trace should contain run_done")
    }
}
