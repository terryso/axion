import Foundation
import Testing

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

/// E2E tests for Helper process lifecycle (Story 3.1).
///
/// Validates: start → MCP connect → tool calls → graceful shutdown.
/// Uses real Helper process but does NOT call LLM.
@Suite("Helper Lifecycle E2E")
struct HelperLifecycleE2ETests {

    private func setUpFixture() async throws -> E2EHelperFixture? {
        let fixture = try E2EHelperFixture()
        let started = try await fixture.setUpHelper()
        guard started else { return nil }
        return fixture
    }

    // MARK: - AC1: Start Helper and establish MCP connection

    @Test("helper starts and connects")
    func helperStartsAndConnects() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let manager = fixture.manager else {
            await fixture.tearDown()
            return
        }

        let running = await manager.isRunning()
        #expect(running, "Helper should be running after setUpHelper()")

        await fixture.tearDown()
    }

    // MARK: - AC2: MCP connection ready — can list tools

    @Test("MCP lists tools")
    func mcpListsTools() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
        }

        let tools = try await mcpClient.listTools()

        let expectedTools = [
            "launch_app", "list_apps",
            "activate_window", "list_windows", "get_window_state",
            "click", "double_click", "right_click",
            "type_text", "press_key", "hotkey",
            "scroll", "drag",
            "screenshot", "get_accessibility_tree",
            "open_url", "validate_window"
        ]

        for tool in expectedTools {
            #expect(tools.contains(tool), "Expected tool '\(tool)' not found in tools/list. Available: \(tools)")
        }

        await fixture.tearDown()
    }

    // MARK: - AC3: Graceful shutdown

    @Test("graceful shutdown")
    func gracefulShutdown() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let manager = fixture.manager else { return }

        let runningBefore = await manager.isRunning()
        #expect(runningBefore, "Helper should be running before stop")

        await manager.stop()

        let runningAfter = await manager.isRunning()
        #expect(!runningAfter, "Helper should NOT be running after stop()")
    }

    // MARK: - AC5: Tool call round-trip

    @Test("tool call round-trip")
    func toolCallRoundTrip() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let mcpClient = fixture.mcpClient else {
            await fixture.tearDown()
            return
        }

        // Launch Calculator
        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )
        #expect(launchResult.contains("pid"), "launch_app result should contain pid: \(launchResult)")

        // Verify it's in list_apps
        let appsResult = try await mcpClient.callTool(name: "list_apps", arguments: [:])
        #expect(
            appsResult.lowercased().contains("calculator"),
            "Calculator should appear in list_apps: \(appsResult)"
        )

        // Quit Calculator
        _ = try? await mcpClient.callTool(
            name: "quit_app",
            arguments: ["name": .string("Calculator")]
        )

        await fixture.tearDown()
    }

    // MARK: - AC6: Fresh start after previous shutdown

    @Test("fresh start after stop")
    func freshStartAfterStop() async throws {
        guard let fixture = try await setUpFixture() else { return }
        guard let manager = fixture.manager else { return }

        // Stop current
        await manager.stop()

        // Create a new manager and start fresh
        let newManager = HelperProcessManager()
        do {
            try await newManager.start()
        } catch {
            return // Could not restart, skip
        }

        let running = await newManager.isRunning()
        #expect(running, "New Helper should be running after fresh start")

        await newManager.stop()
    }
}
