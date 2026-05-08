import XCTest
import MCP
import MCPTool
@testable import AxionHelper
@testable import AxionCore

// ATDD Red-Phase Test Scaffolds for Story 1.3
// AC: list_windows - 列举窗口
// AC: get_window_state - 获取窗口状态
// These tests verify that list_windows and get_window_state tools have real AX-backed
// implementations (not stubs) that interact with macOS window management.
// Priority: P0 (core functionality - window management is required for all UI automation)

final class WindowManagementIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an MCPServer with all tools registered via ToolRegistrar.
    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

    /// Creates a minimal HandlerContext suitable for testing tool execution.
    private func makeTestContext() -> HandlerContext {
        let requestContext = RequestHandlerContext(
            sessionId: nil,
            requestId: .number(1),
            _meta: nil,
            taskId: nil,
            authInfo: nil,
            requestInfo: nil,
            closeResponseStream: nil,
            closeNotificationStream: nil,
            sendNotification: { _ in },
            sendRequest: { _ in Data() }
        )
        return HandlerContext(handlerContext: requestContext, progressToken: nil)
    }

    // MARK: - AC3: list_windows 列举窗口

    // [P0] list_windows 返回窗口列表
    func test_listWindows_returnsWindowList() async throws {
        // Given: 至少有一个应用在运行（Finder 始终有窗口）
        let server = try await makeRegisteredServer()

        // When: 调用 list_windows
        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )

        // Then: 返回窗口列表，不是 stub
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertFalse(
            textContent.lowercased().contains("not yet implemented"),
            "list_windows should have a real implementation, not a stub. Got: \(textContent)"
        )
    }

    // [P0] list_windows 每项包含 window_id、title、bounds
    func test_listWindows_eachWindowHasRequiredFields() async throws {
        // Given: 至少有一个应用窗口存在
        let server = try await makeRegisteredServer()

        // When: 调用 list_windows
        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )

        // Then: 结果为 JSON 格式，每项包含 window_id、title、bounds
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let jsonArray = try JSONSerialization.jsonObject(with: data)

        guard let windows = jsonArray as? [[String: Any]] else {
            XCTFail("list_windows result should be a JSON array. Got: \(textContent)")
            return
        }

        XCTAssertGreaterThan(windows.count, 0, "Should have at least one window")

        for window in windows {
            XCTAssertNotNil(window["window_id"], "Each window should have 'window_id' field")
            XCTAssertNotNil(window["bounds"], "Each window should have 'bounds' field")
        }
    }

    // [P1] list_windows 按 pid 过滤窗口
    func test_listWindows_filterByPid_returnsFilteredResults() async throws {
        // Given: Calculator 已启动
        let server = try await makeRegisteredServer()

        // 先启动 Calculator
        let launchResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        // 从 launch 结果提取 pid
        let launchText = launchResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        // 解析 pid（假设返回 JSON 格式）
        let launchData = launchText.data(using: .utf8)!
        let launchJson = try JSONSerialization.jsonObject(with: launchData) as? [String: Any]
        let pid = try XCTUnwrap(launchJson?["pid"] as? Int)

        // When: 调用 list_windows 传入 pid
        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: ["pid": .int(pid)],
            context: makeTestContext()
        )

        // Then: 只返回该应用的窗口
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertFalse(textContent.isEmpty, "Should return windows for the given pid")

        // 验证结果中的窗口都属于指定 pid
        let data = textContent.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        for window in windows {
            if let windowPid = window["pid"] as? Int {
                XCTAssertEqual(windowPid, pid, "All windows should belong to pid \(pid)")
            }
        }
    }

    // MARK: - AC4: get_window_state 获取窗口状态

    // [P0] get_window_state 返回完整窗口状态
    func test_getWindowState_returnsCompleteState() async throws {
        // Given: Calculator 已启动并有窗口
        let server = try await makeRegisteredServer()

        // 启动 Calculator
        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        // 获取窗口列表
        let windowsResult = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )
        let windowsText = windowsResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        let windowsData = windowsText.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: windowsData) as? [[String: Any]] ?? []
        let firstWindow = try XCTUnwrap(windows.first)
        let windowId = try XCTUnwrap(firstWindow["window_id"] as? Int)

        // When: 调用 get_window_state 传入 window_id
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )

        // Then: 返回完整窗口状态，不是 stub
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertFalse(
            textContent.lowercased().contains("not yet implemented"),
            "get_window_state should have a real implementation, not a stub. Got: \(textContent)"
        )
    }

    // [P0] get_window_state 结果包含 bounds、is_minimized、is_focused、ax_tree
    func test_getWindowState_containsRequiredFields() async throws {
        // Given: Calculator 窗口存在
        let server = try await makeRegisteredServer()

        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let windowsResult = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )
        let windowsText = windowsResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        let windowsData = windowsText.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: windowsData) as? [[String: Any]] ?? []
        let windowId = try XCTUnwrap(windows.first?["window_id"] as? Int)

        // When: 调用 get_window_state
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )

        // Then: 结果包含 bounds, is_minimized, is_focused, ax_tree
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["bounds"], "Window state should include 'bounds'")
        XCTAssertNotNil(json?["is_minimized"], "Window state should include 'is_minimized'")
        XCTAssertNotNil(json?["is_focused"], "Window state should include 'is_focused'")
        XCTAssertNotNil(json?["ax_tree"], "Window state should include 'ax_tree'")
    }

    // [P1] get_window_state 的 bounds 包含 x, y, width, height
    func test_getWindowState_boundsContainsPositionAndSize() async throws {
        // Given: Calculator 窗口存在
        let server = try await makeRegisteredServer()

        _ = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let windowsResult = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )
        let windowsText = windowsResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        let windowsData = windowsText.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: windowsData) as? [[String: Any]] ?? []
        let windowId = try XCTUnwrap(windows.first?["window_id"] as? Int)

        // When: 获取窗口状态
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )

        // Then: bounds 包含 x, y, width, height
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let bounds = try XCTUnwrap(json?["bounds"] as? [String: Any])

        XCTAssertNotNil(bounds["x"], "bounds should have 'x'")
        XCTAssertNotNil(bounds["y"], "bounds should have 'y'")
        XCTAssertNotNil(bounds["width"], "bounds should have 'width'")
        XCTAssertNotNil(bounds["height"], "bounds should have 'height'")
    }

    // [P1] get_window_state 不存在的 window_id 返回错误
    func test_getWindowState_invalidWindowId_returnsError() async throws {
        // Given: get_window_state 工具已注册
        let server = try await makeRegisteredServer()

        // When: 传入一个不存在的 window_id
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(-1)],
            context: makeTestContext()
        )

        // Then: 返回错误结果
        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        XCTAssertTrue(
            textContent.lowercased().contains("error") || textContent.lowercased().contains("not found"),
            "get_window_state should return error for invalid window_id. Got: \(textContent)"
        )
    }

    // MARK: - Integration: launch → list_windows → get_window_state 完整链路

    // [P0] 完整链路: 启动应用 → 查看窗口 → 获取窗口状态
    func test_fullWorkflow_launchToListWindowsToGetState() async throws {
        // Given: 所有应用管理工具已注册
        let server = try await makeRegisteredServer()

        // Step 1: 启动 Calculator
        let launchResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )
        let launchText = launchResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        XCTAssertFalse(launchText.lowercased().contains("not yet implemented"))
        XCTAssertFalse(launchText.lowercased().contains("error"))

        // Step 2: 列举窗口，找到 Calculator 的窗口
        let windowsResult = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )
        let windowsText = windowsResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        XCTAssertFalse(windowsText.lowercased().contains("not yet implemented"))

        let windowsData = windowsText.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: windowsData) as? [[String: Any]] ?? []
        let calcWindow = try XCTUnwrap(
            windows.first { ($0["title"] as? String ?? "").lowercased().contains("calculator") || ($0["app_name"] as? String ?? "").lowercased().contains("calculator") },
            "Should find Calculator window in list. Windows: \(windows)"
        )
        let windowId = try XCTUnwrap(calcWindow["window_id"] as? Int)

        // Step 3: 获取 Calculator 窗口状态
        let stateResult = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )
        let stateText = stateResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        XCTAssertFalse(stateText.lowercased().contains("not yet implemented"))

        // 验证窗口状态包含 ax_tree
        let stateData = stateText.data(using: .utf8)!
        let stateJson = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        XCTAssertNotNil(stateJson?["ax_tree"], "Window state should include ax_tree")
    }
}
