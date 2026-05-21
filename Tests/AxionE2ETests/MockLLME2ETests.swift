import Foundation
import Testing

import AxionCore
@testable import AxionCLI
import enum OpenAgentSDK.SDKMessage

/// E2E tests with mock LLM responses and real Helper process.
///
/// Tests the full message pipeline: mock Agent stream → output handler + trace recorder,
/// then verifies output formatting and trace file integrity.
/// Real Helper is used when MCP tool calls are made through the SDK pipeline.
///
/// Prerequisites:
/// - AxionHelper.app built at .build/AxionHelper.app
/// - macOS Accessibility permissions granted
@Suite("Mock LLM E2E")
struct MockLLME2ETests {

    private func setUpFixture() async throws -> E2EHelperFixture? {
        let fixture = try E2EHelperFixture()
        let started = try await fixture.setUpHelper()
        guard started else { return nil }
        return fixture
    }

    // MARK: - 1. Launch App and Verify (Happy Path)

    @Test("E2E launch app and verify")
    func e2eLaunchAppAndVerify() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
        }

        // Use real Helper to launch Calculator and capture result
        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        // Build mock message sequence simulating a full agent run
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(write: capturing.write)

        handler.displayRunStart(runId: "e2e-test-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            .assistant(.init(text: "I'll launch Calculator for you.", model: "mock", stopReason: "tool_use")),
            .toolUse(.init(toolName: "launch_app", toolUseId: "tu-1", input: #"{"app_name":"Calculator"}"#)),
            .toolResult(.init(toolUseId: "tu-1", content: launchResult, isError: false)),
            .assistant(.init(text: "Calculator is now open.", model: "mock", stopReason: "end_turn")),
            .result(.init(subtype: .success, text: "Calculator launched", usage: nil, numTurns: 1, durationMs: 1500)),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler)
        await runner.run(messages: messages)

        // Verify output contains expected content
        #expect(capturing.contains("Open Calculator"), "Output should contain task description")
        #expect(capturing.contains("launch_app") || capturing.contains("执行"), "Output should contain tool execution info")
        #expect(capturing.contains("运行结束"), "Output should show completion")

        // Clean up: quit Calculator
        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
        await fixture.tearDown()
    }

    // MARK: - 2. Dryrun Mode

    @Test("E2E dryrun mode")
    func e2eDryrunMode() async throws {
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(write: capturing.write)

        handler.displayRunStart(runId: "e2e-dryrun-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            .partialMessage(.init(text: "Planning")),
            .partialMessage(.init(text: " to open Calculator...")),
            .assistant(.init(text: "Plan: 1. Launch Calculator using launch_app tool.", model: "mock", stopReason: "end_turn")),
            .result(.init(subtype: .success, text: "Dryrun complete — would launch Calculator.", usage: nil, numTurns: 1, durationMs: 200)),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler)
        await runner.run(messages: messages)

        // Verify output
        #expect(capturing.contains("运行结束"), "Should show completion")
        #expect(capturing.contains("Planning"), "Should show planning text")
    }

    // MARK: - 3. Multi-Step Keyboard Operations

    @Test("E2E multi-step typing")
    func e2eMultiStepTyping() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
        }

        // Launch Calculator first
        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )

        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(write: capturing.write)

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

        let runner = E2EPipelineRunner(outputHandler: handler)
        await runner.run(messages: messages)

        // Verify all steps appear in output
        #expect(capturing.contains("launch_app"), "Should show launch_app step")
        #expect(capturing.contains("press_key"), "Should show press_key step")
        #expect(capturing.contains("hotkey"), "Should show hotkey step")
        #expect(capturing.contains("运行结束"), "Should show completion")

        // Clean up
        _ = try? await mcpClient.callTool(name: "quit_app", arguments: ["name": .string("Calculator")])
        await fixture.tearDown()
    }

    // MARK: - 4. Error Recovery

    @Test("E2E error recovery")
    func e2eErrorRecovery() async throws {
        let capturing = CapturingOutput()
        let handler = SDKTerminalOutputHandler(write: capturing.write)

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

        let runner = E2EPipelineRunner(outputHandler: handler)
        await runner.run(messages: messages)

        #expect(capturing.contains("错误") || capturing.contains("error") || capturing.contains("App not found"),
                       "Output should indicate the error step")
        #expect(capturing.contains("运行结束"), "Should complete despite error")
    }

    // MARK: - 5. JSON Output Format

    @Test("E2E JSON output format")
    func e2eJsonOutputFormat() async throws {
        let capturing = CapturingJSONOutput()
        let handler = SDKJSONOutputHandler(write: capturing.write)

        handler.displayRunStart(runId: "e2e-json-001", task: "Open Calculator")

        let messages: [SDKMessage] = [
            E2EMessages.assistant("Opening Calculator"),
            E2EMessages.toolUse("launch_app", id: "t1"),
            E2EMessages.toolResult(id: "t1", content: #"{"pid":12345}"#),
            E2EMessages.successResult(text: "Done"),
        ]

        let runner = E2EPipelineRunner(outputHandler: handler)
        await runner.run(messages: messages)

        guard let jsonStr = capturing.lastJSON else {
            Issue.record("JSON output handler should produce output")
            return
        }

        // Verify it's valid JSON
        let data = jsonStr.data(using: .utf8)!
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["runId"] as? String == "e2e-json-001")
        #expect(json["task"] as? String == "Open Calculator")
        #expect(json["status"] as? String == "success")
        #expect(json["numTurns"] as? Int == 1)

        let steps = try #require(json["steps"] as? [[String: Any]])
        #expect(!steps.isEmpty, "Should have recorded tool steps")
        #expect(steps[0]["tool"] as? String == "launch_app")
    }
}
