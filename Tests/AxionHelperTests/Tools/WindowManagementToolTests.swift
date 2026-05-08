import Foundation
import MCP
import MCPTool
import XCTest
@testable import AxionHelper
@testable import AxionCore

// Unit tests for list_windows and get_window_state tools using mock services.
// These tests do NOT interact with real macOS windows — all system interaction is mocked.
// Priority: P0 (core tool wiring)

@MainActor
final class WindowManagementToolTests: XCTestCase {

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

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined()
    }

    private static let sampleWindow = WindowInfo(
        windowId: 42,
        pid: 1234,
        title: "Calculator",
        appName: "Calculator",
        bundleId: "com.apple.calculator",
        bounds: WindowBounds(x: 100, y: 100, width: 300, height: 400)
    )

    private static let sampleState = WindowState(
        windowId: 42,
        pid: 1234,
        title: "Calculator",
        bounds: WindowBounds(x: 100, y: 100, width: 300, height: 400),
        isMinimized: false,
        isFocused: true,
        axTree: AXElement(role: "AXWindow", title: "Calculator", value: nil, bounds: nil, children: [])
    )

    // MARK: - list_windows

    func test_listWindows_returnsJsonArray() async throws {
        let window = Self.sampleWindow
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [window] },
                getWindowStateHandler: { _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )

        let text = textContent(result)
        let data = text.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertEqual(windows?.count, 1)
        XCTAssertEqual(windows?[0]["window_id"] as? Int, 42)
    }

    func test_listWindows_filterByPid() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { pid in
                    [WindowInfo(
                        windowId: 1, pid: pid ?? 0, title: "W",
                        appName: nil, bundleId: nil,
                        bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100)
                    )]
                },
                getWindowStateHandler: { _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "list_windows",
            arguments: ["pid": .int(1234)],
            context: makeTestContext()
        )
    }

    func test_listWindows_eachWindowHasRequiredFields() async throws {
        let window = Self.sampleWindow
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [window] },
                getWindowStateHandler: { _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "list_windows",
            arguments: nil,
            context: makeTestContext()
        )

        let text = textContent(result)
        let data = text.data(using: .utf8)!
        let windows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        for window in windows {
            XCTAssertNotNil(window["window_id"], "Each window should have window_id")
            XCTAssertNotNil(window["bounds"], "Each window should have bounds")
        }
    }

    // MARK: - get_window_state

    func test_getWindowState_returnsCompleteState() async throws {
        let state = Self.sampleState
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { windowId in
                    guard windowId == 42 else { throw AccessibilityEngineError.windowNotFound(windowId: windowId) }
                    return state
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(42)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertNotNil(json?["bounds"])
        XCTAssertNotNil(json?["is_minimized"])
        XCTAssertNotNil(json?["is_focused"])
        XCTAssertNotNil(json?["ax_tree"])
    }

    func test_getWindowState_invalidWindowId_returnsErrorJson() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { windowId in
                    throw AccessibilityEngineError.windowNotFound(windowId: windowId)
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(-1)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "window_not_found")
        XCTAssertNotNil(json?["suggestion"])
    }

    func test_getWindowState_boundsContainsPositionAndSize() async throws {
        let state = Self.sampleState
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in state }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(42)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        let bounds = try XCTUnwrap(json?["bounds"] as? [String: Any])

        XCTAssertNotNil(bounds["x"])
        XCTAssertNotNil(bounds["y"])
        XCTAssertNotNil(bounds["width"])
        XCTAssertNotNil(bounds["height"])
    }
}
