import Foundation
import MCP
import MCPTool
import Testing
@testable import AxionHelper
@testable import AxionCore

final class ThreadSafeArray<T>: @unchecked Sendable {
    private var items: [T] = []
    private let lock = NSLock()
    func append(_ item: T) { lock.withLock { items.append(item) } }
    var count: Int { lock.withLock { items.count } }
    subscript(index: Int) -> T { lock.withLock { items[index] } }
}

@MainActor
extension ToolsTests {
@Suite("WindowManagementTool")
struct WindowManagementToolTests {

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

    @Test("list windows returns JSON array")
    func listWindowsReturnsJsonArray() async throws {
        let window = Self.sampleWindow
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [window] },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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

        #expect(windows?.count == 1)
        #expect(windows?[0]["window_id"] as? Int == 42)
    }

    @Test("list windows filter by pid")
    func listWindowsFilterByPid() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { pid in
                    [WindowInfo(
                        windowId: 1, pid: pid ?? 0, title: "W",
                        appName: nil, bundleId: nil,
                        bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100)
                    )]
                },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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

    @Test("list windows each window has required fields")
    func listWindowsEachWindowHasRequiredFields() async throws {
        let window = Self.sampleWindow
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [window] },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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
            #expect(window["window_id"] != nil)
            #expect(window["bounds"] != nil)
        }
    }

    @Test("get window state returns complete state")
    func getWindowStateReturnsCompleteState() async throws {
        let state = Self.sampleState
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { windowId in
                    guard windowId == 42 else { throw AccessibilityEngineError.windowNotFound(windowId: windowId) }
                    return state
                },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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

        #expect(json?["bounds"] != nil)
        #expect(json?["is_minimized"] != nil)
        #expect(json?["is_focused"] != nil)
        #expect(json?["ax_tree"] != nil)
    }

    @Test("get window state invalid window id returns error JSON")
    func getWindowStateInvalidWindowIdReturnsErrorJson() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { windowId in
                    throw AccessibilityEngineError.windowNotFound(windowId: windowId)
                },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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

        #expect(json?["error"] as? String == "window_not_found")
        #expect(json?["suggestion"] != nil)
    }

    @Test("get window state bounds contains position and size")
    func getWindowStateBoundsContainsPositionAndSize() async throws {
        let state = Self.sampleState
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in state },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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
        let bounds = try #require(json?["bounds"] as? [String: Any])

        #expect(bounds["x"] != nil)
        #expect(bounds["y"] != nil)
        #expect(bounds["width"] != nil)
        #expect(bounds["height"] != nil)
    }

    @Test("resize window returns updated bounds")
    func resizeWindowReturnsUpdatedBounds() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in WindowState(
                    windowId: 42, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    #expect(windowId == 42)
                    #expect(x == 100)
                    #expect(y == 200)
                    #expect(width == nil)
                    #expect(height == nil)
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "resize_window",
            arguments: ["window_id": .int(42), "x": .int(100), "y": .int(200)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        #expect(json?["window_id"] as? Int == 42)
    }

    @Test("arrange windows tile left right")
    func arrangeWindowsTileLeftRight() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 960, height: 1080),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-left-right"), "window_ids": .array([.int(1), .int(2)])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        #expect(json?["layout"] as? String == "tile-left-right")
        #expect(setBoundsCalls.count == 2)
        #expect(setBoundsCalls[0].windowId == 1)
        #expect(setBoundsCalls[1].windowId == 2)
    }

    @Test("arrange windows unknown layout returns error")
    func arrangeWindowsUnknownLayoutReturnsError() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("circular"), "window_ids": .array([.int(1), .int(2)])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["error"] as? String == "invalid_layout")
    }

    @Test("arrange windows tile top bottom")
    func arrangeWindowsTileTopBottom() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 540),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-top-bottom"), "window_ids": .array([.int(10), .int(20)])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        #expect(json?["layout"] as? String == "tile-top-bottom")
        #expect(setBoundsCalls.count == 2)
        #expect(setBoundsCalls[0].windowId == 10)
        #expect(setBoundsCalls[1].windowId == 20)
    }

    @Test("arrange windows cascade")
    func arrangeWindowsCascade() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("cascade"), "window_ids": .array([.int(1), .int(2), .int(3)])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        #expect(json?["layout"] as? String == "cascade")
        #expect(setBoundsCalls.count == 3)
        #expect(setBoundsCalls[0].x! == 0)
        #expect(setBoundsCalls[1].x! - setBoundsCalls[0].x! == 30)
        #expect(setBoundsCalls[2].x! - setBoundsCalls[1].x! == 30)
        #expect(setBoundsCalls[1].y! - setBoundsCalls[0].y! == 30)
        #expect(setBoundsCalls[2].y! - setBoundsCalls[1].y! == 30)
    }

    @Test("arrange windows insufficient windows returns error")
    func arrangeWindowsInsufficientWindowsReturnsError() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-left-right"), "window_ids": .array([.int(1)])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["error"] as? String == "invalid_params")
    }

    @Test("resize window all parameters updates all fields")
    func resizeWindowAllParametersUpdatesAllFields() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in WindowState(
                    windowId: 99, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 50, y: 60, width: 700, height: 500),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "resize_window",
            arguments: [
                "window_id": .int(99),
                "x": .int(50),
                "y": .int(60),
                "width": .int(700),
                "height": .int(500),
            ],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        #expect(setBoundsCalls.count == 1)
        #expect(setBoundsCalls[0].windowId == 99)
        #expect(setBoundsCalls[0].x == 50)
        #expect(setBoundsCalls[0].y == 60)
        #expect(setBoundsCalls[0].width == 700)
        #expect(setBoundsCalls[0].height == 500)
    }

    @Test("resize window only dimensions position untouched")
    func resizeWindowOnlyDimensionsPositionUntouched() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in WindowState(
                    windowId: 7, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 200, y: 300, width: 400, height: 300),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "resize_window",
            arguments: ["window_id": .int(7), "width": .int(400), "height": .int(300)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        #expect(setBoundsCalls[0].x == nil)
        #expect(setBoundsCalls[0].y == nil)
        #expect(setBoundsCalls[0].width == 400)
        #expect(setBoundsCalls[0].height == 300)
    }

    @Test("resize window window not found returns error")
    func resizeWindowWindowNotFoundReturnsError() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { windowId in
                    throw AccessibilityEngineError.windowNotFound(windowId: windowId)
                },
                getAXTreeHandler: { _, _ in fatalError("should not be called") },
                setWindowBoundsHandler: { _, _, _, _, _ in }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "resize_window",
            arguments: ["window_id": .int(9999), "x": .int(0), "y": .int(0)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["error"] as? String == "window_not_found")
        #expect(json?["suggestion"] != nil)
    }

    @Test("arrange windows tile left right validates coordinates")
    func arrangeWindowsTileLeftRightValidatesCoordinates() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 500, height: 500),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-left-right"), "window_ids": .array([.int(1), .int(2)])],
            context: makeTestContext()
        )

        #expect(setBoundsCalls.count == 2)
        #expect(setBoundsCalls[0].x == 0)
        #expect(setBoundsCalls[0].y! >= 0)
        #expect(setBoundsCalls[1].x! > setBoundsCalls[0].x!)
        #expect(setBoundsCalls[0].height == setBoundsCalls[1].height)
    }

    @Test("arrange windows tile top bottom validates coordinates")
    func arrangeWindowsTileTopBottomValidatesCoordinates() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 500, height: 500),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-top-bottom"), "window_ids": .array([.int(10), .int(20)])],
            context: makeTestContext()
        )

        #expect(setBoundsCalls.count == 2)
        #expect(setBoundsCalls[0].x == 0)
        #expect(setBoundsCalls[0].y! >= 0)
        #expect(setBoundsCalls[1].y! > setBoundsCalls[0].y!)
        #expect(setBoundsCalls[0].width == setBoundsCalls[1].width)
    }

    @Test("arrange windows empty window ids returns error")
    func arrangeWindowsEmptyWindowIdsReturnsError() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-left-right"), "window_ids": .array([])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["error"] as? String == "invalid_params")
    }

    @Test("arrange windows response contains windows array")
    func arrangeWindowsResponseContainsWindowsArray() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 100, y: 200, width: 300, height: 400),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { _, _, _, _, _ in }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("cascade"), "window_ids": .array([.int(5), .int(6)])],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
        #expect(json?["success"] as? Bool == true)
        let windows = try #require(json?["windows"] as? [[String: Any]])
        #expect(windows.count == 2)
        #expect(windows[0]["window_id"] as? Int == 5)
        #expect(windows[1]["window_id"] as? Int == 6)
        for win in windows {
            #expect(win["x"] != nil)
            #expect(win["y"] != nil)
            #expect(win["width"] != nil)
            #expect(win["height"] != nil)
        }
    }

    @Test("workflow resize then arrange")
    func workflowResizeThenArrange() async throws {
        let setBoundsCalls = ThreadSafeArray<(windowId: Int, x: Int?, y: Int?, width: Int?, height: Int?)>()
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { wid in WindowState(
                    windowId: wid, pid: 1234, title: "Test",
                    bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600),
                    isMinimized: false, isFocused: true, axTree: nil
                ) },
                getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: []) },
                setWindowBoundsHandler: { windowId, x, y, width, height in
                    setBoundsCalls.append((windowId, x, y, width, height))
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()

        let resizeResult = try await server.toolRegistry.execute(
            "resize_window",
            arguments: ["window_id": .int(1), "width": .int(640), "height": .int(480)],
            context: makeTestContext()
        )
        let resizeText = textContent(resizeResult)
        let resizeJson = try JSONSerialization.jsonObject(with: resizeText.data(using: .utf8)!) as? [String: Any]
        #expect(resizeJson?["success"] as? Bool == true)

        setBoundsCalls.append((-1, nil, nil, nil, nil))
        let arrangeResult = try await server.toolRegistry.execute(
            "arrange_windows",
            arguments: ["layout": .string("tile-left-right"), "window_ids": .array([.int(1), .int(2)])],
            context: makeTestContext()
        )
        let arrangeText = textContent(arrangeResult)
        let arrangeJson = try JSONSerialization.jsonObject(with: arrangeText.data(using: .utf8)!) as? [String: Any]
        #expect(arrangeJson?["success"] as? Bool == true)
        #expect(arrangeJson?["layout"] as? String == "tile-left-right")
    }

    @Test("list windows returns z order")
    func listWindowsReturnsZOrder() async throws {
        let windows = [
            WindowInfo(windowId: 1, pid: 100, title: "Safari", appName: "Safari", bundleId: "com.apple.Safari", bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600), zOrder: 0),
            WindowInfo(windowId: 2, pid: 200, title: "TextEdit", appName: "TextEdit", bundleId: "com.apple.TextEdit", bounds: WindowBounds(x: 100, y: 100, width: 400, height: 300), zOrder: 1),
        ]
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in windows },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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
        let windowsJson = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        #expect(windowsJson.count == 2)
        #expect(windowsJson[0]["z_order"] as? Int == 0)
        #expect(windowsJson[1]["z_order"] as? Int == 1)
    }

    @Test("list windows multiple apps returns all windows with different z orders")
    func listWindowsMultipleAppsReturnsAllWindowsWithDifferentZOrders() async throws {
        let windows = [
            WindowInfo(windowId: 10, pid: 100, title: "Chrome", appName: "Chrome", bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 1920, height: 1080), zOrder: 0),
            WindowInfo(windowId: 20, pid: 200, title: "Notes", appName: "Notes", bundleId: nil, bounds: WindowBounds(x: 50, y: 50, width: 600, height: 400), zOrder: 1),
            WindowInfo(windowId: 30, pid: 100, title: "Chrome DevTools", appName: "Chrome", bundleId: nil, bounds: WindowBounds(x: 0, y: 0, width: 400, height: 600), zOrder: 2),
        ]
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in windows },
                getWindowStateHandler: { _ in fatalError("should not be called") },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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
        let windowsJson = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        #expect(windowsJson.count == 3)
        let zOrders = windowsJson.compactMap { $0["z_order"] as? Int }
        #expect(zOrders == [0, 1, 2])
        #expect(windowsJson[0]["app_name"] as? String == "Chrome")
        #expect(windowsJson[1]["app_name"] as? String == "Notes")
    }

    @Test("get window state returns app name")
    func getWindowStateReturnsAppName() async throws {
        let state = WindowState(
            windowId: 42, pid: 1234, title: "Calculator",
            bounds: WindowBounds(x: 100, y: 100, width: 300, height: 400),
            isMinimized: false, isFocused: true,
            axTree: AXElement(role: "AXWindow", title: "Calculator", value: nil, bounds: nil, children: []),
            appName: "Calculator"
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in state },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
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

        #expect(json?["app_name"] as? String == "Calculator")
        #expect(json?["appName"] == nil)
    }

    @Test("get window state minimized window returns state with app name")
    func getWindowStateMinimizedWindowReturnsStateWithAppName() async throws {
        let state = WindowState(
            windowId: 99, pid: 5678, title: "Notes",
            bounds: WindowBounds(x: 0, y: 0, width: 600, height: 400),
            isMinimized: true, isFocused: false,
            axTree: nil,
            appName: "Notes"
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in state },
                getAXTreeHandler: { _, _ in fatalError("should not be called") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_window_state",
            arguments: ["window_id": .int(99)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        #expect(json?["is_minimized"] as? Bool == true)
        #expect(json?["app_name"] as? String == "Notes")
        #expect(json?["window_id"] as? Int == 99)
    }
}
}
