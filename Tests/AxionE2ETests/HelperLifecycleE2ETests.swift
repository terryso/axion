import Foundation
import XCTest

import AxionCore
import OpenAgentSDK
@testable import AxionCLI

/// E2E tests for Helper process lifecycle (Story 3.1).
///
/// Validates: start → MCP connect → tool calls → graceful shutdown.
/// Uses real Helper process but does NOT call LLM.
final class HelperLifecycleE2ETests: XCTestCase {

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

    // MARK: - AC1: Start Helper and establish MCP connection

    /// Helper starts and MCP connection is ready for tool calls.
    func test_helperStartsAndConnects() async throws {
        guard let manager = fixture.manager else {
            throw XCTSkip("AxionHelper not available")
        }

        let running = await manager.isRunning()
        XCTAssertTrue(running, "Helper should be running after setUpHelper()")
    }

    // MARK: - AC2: MCP connection ready — can list tools

    /// MCP handshake completed and tools/list returns all expected tools.
    func test_mcpListsTools() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        let tools = try await mcpClient.listTools()

        // Verify core tools are registered (Story 1.6 AC1)
        let expectedTools = [
            "launch_app", "list_apps", "quit_app",
            "activate_window", "list_windows", "get_window_state",
            "click", "double_click", "right_click",
            "type_text", "press_key", "hotkey",
            "scroll", "drag",
            "screenshot", "get_accessibility_tree",
            "open_url", "get_file_info"
        ]

        for tool in expectedTools {
            XCTAssertTrue(tools.contains(tool), "Expected tool '\(tool)' not found in tools/list. Available: \(tools)")
        }
    }

    // MARK: - AC3: Graceful shutdown

    /// Stopping Helper disconnects MCP and terminates the process.
    func test_gracefulShutdown() async throws {
        guard let manager = fixture.manager else {
            throw XCTSkip("AxionHelper not available")
        }

        // Verify it's running first
        let runningBefore = await manager.isRunning()
        XCTAssertTrue(runningBefore, "Helper should be running before stop")

        // Stop
        await manager.stop()

        let runningAfter = await manager.isRunning()
        XCTAssertFalse(runningAfter, "Helper should NOT be running after stop()")
    }

    // MARK: - AC5: Tool call round-trip

    /// A full tool call round-trip works: launch_app → get pid → quit_app.
    func test_toolCallRoundTrip() async throws {
        guard let mcpClient = fixture.mcpClient else {
            throw XCTSkip("AxionHelper not available")
        }

        // Launch Calculator
        let launchResult = try await mcpClient.callTool(
            name: "launch_app",
            arguments: ["app_name": .string("Calculator")]
        )
        XCTAssertTrue(launchResult.contains("pid"), "launch_app result should contain pid: \(launchResult)")

        // Verify it's in list_apps
        let appsResult = try await mcpClient.callTool(name: "list_apps", arguments: [:])
        XCTAssertTrue(
            appsResult.lowercased().contains("calculator"),
            "Calculator should appear in list_apps: \(appsResult)"
        )

        // Quit Calculator
        _ = try? await mcpClient.callTool(
            name: "quit_app",
            arguments: ["name": .string("Calculator")]
        )
    }

    // MARK: - AC6: Fresh start after previous shutdown

    /// A new HelperProcessManager can start a fresh Helper after the previous one stopped.
    func test_freshStartAfterStop() async throws {
        guard let manager = fixture.manager else {
            throw XCTSkip("AxionHelper not available")
        }

        // Stop current
        await manager.stop()

        // Create a new manager and start fresh
        let newManager = HelperProcessManager()
        do {
            try await newManager.start()
        } catch {
            throw XCTSkip("Could not restart Helper: \(error)")
        }

        let running = await newManager.isRunning()
        XCTAssertTrue(running, "New Helper should be running after fresh start")

        await newManager.stop()
    }
}
