import Foundation
import Testing
import MCP
import MCPTool
@testable import AxionHelper
@testable import AxionCore

@Suite("WindowManagement Integration")
struct WindowManagementIntegrationTests {

    // MARK: - Helpers

    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

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

    @Test("list_windows returns window list")
    func listWindowsReturnsWindowList() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(!textContent.lowercased().contains("not yet implemented"),
                "list_windows should have a real implementation, not a stub. Got: \(textContent)")
    }

    @Test("list_windows each window has required fields")
    func listWindowsEachWindowHasRequiredFields() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let jsonArray = try JSONSerialization.jsonObject(with: data)

        guard let windows = jsonArray as? [[String: Any]] else {
            Issue.record("list_windows result should be a JSON array. Got: \(textContent)")
            return
        }

        #expect(windows.count > 0, "Should have at least one window")

        for window in windows {
            #expect(window["window_id"] != nil, "Each window should have 'window_id' field")
            #expect(window["bounds"] != nil, "Each window should have 'bounds' field")
        }
    }

    @Test("list_windows filter by pid returns filtered results")
    func listWindowsFilterByPid() async throws {
        let server = try await makeRegisteredServer()

        let launchResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )

        let launchText = launchResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let launchData = launchText.data(using: .utf8)!
        let launchJson = try JSONSerialization.jsonObject(with: launchData) as? [String: Any]
        guard let pid = launchJson?["pid"] as? Int else { return }

        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: ["pid": .int(pid)],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(!textContent.isEmpty, "Should return windows for the given pid")

        let data = textContent.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        for window in windows {
            if let windowPid = window["pid"] as? Int {
                #expect(windowPid == pid, "All windows should belong to pid \(pid)")
            }
        }
    }

    // MARK: - AC4: get_window_state 获取窗口状态

    @Test("get_window_state returns complete state")
    func getWindowStateReturnsCompleteState() async throws {
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
        guard let firstWindow = windows.first,
              let windowId = firstWindow["window_id"] as? Int else { return }

        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(!textContent.lowercased().contains("not yet implemented"),
                "get_window_state should have a real implementation, not a stub. Got: \(textContent)")
    }

    @Test("get_window_state contains required fields")
    func getWindowStateContainsRequiredFields() async throws {
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
        guard let windowId = windows.first?["window_id"] as? Int else { return }

        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["bounds"] != nil, "Window state should include 'bounds'")
        #expect(json?["is_minimized"] != nil, "Window state should include 'is_minimized'")
        #expect(json?["is_focused"] != nil, "Window state should include 'is_focused'")
        #expect(json?["ax_tree"] != nil, "Window state should include 'ax_tree'")
    }

    @Test("get_window_state bounds contains position and size")
    func getWindowStateBoundsContainsPositionAndSize() async throws {
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
        guard let windowId = windows.first?["window_id"] as? Int else { return }

        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        let data = textContent.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let bounds = json?["bounds"] as? [String: Any] else {
            Issue.record("Should have bounds")
            return
        }

        #expect(bounds["x"] != nil, "bounds should have 'x'")
        #expect(bounds["y"] != nil, "bounds should have 'y'")
        #expect(bounds["width"] != nil, "bounds should have 'width'")
        #expect(bounds["height"] != nil, "bounds should have 'height'")
    }

    @Test("get_window_state invalid window ID returns error")
    func getWindowStateInvalidWindowIdReturnsError() async throws {
        let server = try await makeRegisteredServer()

        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(-1)],
            context: makeTestContext()
        )

        let textContent = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()

        #expect(
            textContent.lowercased().contains("error") || textContent.lowercased().contains("not found"),
            "get_window_state should return error for invalid window_id. Got: \(textContent)"
        )
    }

    // MARK: - Integration: launch → list_windows → get_window_state 完整链路

    @Test("full workflow launch to list windows to get state")
    func fullWorkflowLaunchToListWindowsToGetState() async throws {
        let server = try await makeRegisteredServer()

        let launchResult = try await server.toolRegistry.execute(
            "launch_app",
            arguments: ["app_name": .string("Calculator")],
            context: makeTestContext()
        )
        let launchText = launchResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        #expect(!launchText.lowercased().contains("not yet implemented"))
        #expect(!launchText.lowercased().contains("error"))

        let windowsResult = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )
        let windowsText = windowsResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        #expect(!windowsText.lowercased().contains("not yet implemented"))

        let windowsData = windowsText.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: windowsData) as? [[String: Any]] ?? []
        guard let calcWindow = windows.first(where: {
            ($0["title"] as? String ?? "").lowercased().contains("calculator") || ($0["app_name"] as? String ?? "").lowercased().contains("calculator")
        }) else { return }
        guard let windowId = calcWindow["window_id"] as? Int else { return }

        let stateResult = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(windowId)],
            context: makeTestContext()
        )
        let stateText = stateResult.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
        #expect(!stateText.lowercased().contains("not yet implemented"))

        let stateData = stateText.data(using: .utf8)!
        let stateJson = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateJson?["ax_tree"] != nil, "Window state should include ax_tree")
    }
}
