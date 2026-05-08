import Foundation
import MCP
import MCPTool
import XCTest
@testable import AxionHelper
@testable import AxionCore

// ATDD Red-Phase Test Scaffolds for Story 1.5
// AC: #1 - screenshot 窗口截图 (base64, <=5MB)
// AC: #2 - screenshot 全屏截图 (base64)
// AC: #3 - get_accessibility_tree 完整树 (role/title/value/bounds/children)
// AC: #4 - get_accessibility_tree 截断 (maxNodes=500)
// AC: #5 - open_url URL 打开 (默认浏览器)
// These tests verify AxionHelper's screenshot, AX tree, and URL opening tools
// using mock services — no real macOS system calls.
// Priority: P0 (core tool wiring for screenshot, get_accessibility_tree, open_url)

@MainActor
final class ScreenshotUrlToolTests: XCTestCase {

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

    /// A short valid base64 string for mock screenshot results.
    private let mockBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    /// Creates a MockScreenshotCapture that returns a valid base64 string for all calls.
    private func makeSuccessScreenshotMock() -> MockScreenshotCapture {
        let base64 = mockBase64
        return MockScreenshotCapture(
            captureWindowHandler: { _ in base64 },
            captureFullScreenHandler: { base64 }
        )
    }

    /// Creates a MockURLOpener that succeeds for all calls.
    private func makeSuccessURLOpenerMock() -> MockURLOpener {
        MockURLOpener(openURLHandler: { _ in })
    }

    // MARK: - AC1: screenshot 窗口截图

    // [P0] screenshot with window_id returns base64 encoded image data
    func test_screenshot_withWindowId_returnsBase64Json() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot",
            arguments: ["window_id": .int(12345)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "screenshot")
        XCTAssertNotNil(json?["image_data"] as? String, "Should contain image_data field with base64")
    }

    // [P0] screenshot with window_id passes correct window_id to service
    func test_screenshot_withWindowId_passesCorrectWindowId() async throws {
        let box = Box<Int?>(value: nil)
        let base64 = mockBase64
        let mock = MockScreenshotCapture(
            captureWindowHandler: { windowId in
                box.value = windowId
                return base64
            },
            captureFullScreenHandler: { base64 }
        )
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: mock,
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "screenshot",
            arguments: ["window_id": .int(42)],
            context: makeTestContext()
        )

        XCTAssertEqual(box.value, 42, "Should pass window_id=42 to captureWindow")
    }

    // [P0] screenshot with invalid window_id returns window_capture_failed error
    func test_screenshot_invalidWindowId_returnsErrorJson() async throws {
        let base64 = mockBase64
        let mock = MockScreenshotCapture(
            captureWindowHandler: { windowId in
                throw ScreenshotError.windowCaptureFailed(windowId: windowId)
            },
            captureFullScreenHandler: { base64 }
        )
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: mock,
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot",
            arguments: ["window_id": .int(99999)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "window_capture_failed")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC2: screenshot 全屏截图

    // [P0] screenshot without window_id returns full screen base64
    func test_screenshot_noWindowId_returnsFullScreenBase64Json() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot",
            arguments: [:],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "screenshot")
        XCTAssertNotNil(json?["image_data"] as? String)
    }

    // [P0] screenshot without window_id calls captureFullScreen (not captureWindow)
    func test_screenshot_noWindowId_callsCaptureFullScreen() async throws {
        let box = Box<Bool>(value: false)
        let base64 = mockBase64
        let mock = MockScreenshotCapture(
            captureWindowHandler: { _ in fatalError("Should not call captureWindow") },
            captureFullScreenHandler: {
                box.value = true
                return base64
            }
        )
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: mock,
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "screenshot",
            arguments: [:],
            context: makeTestContext()
        )

        XCTAssertTrue(box.value, "Should call captureFullScreen when no window_id")
    }

    // [P0] screenshot full screen failure returns fullscreen_capture_failed error
    func test_screenshot_fullScreenFailure_returnsErrorJson() async throws {
        let base64 = mockBase64
        let mock = MockScreenshotCapture(
            captureWindowHandler: { _ in base64 },
            captureFullScreenHandler: {
                throw ScreenshotError.fullScreenCaptureFailed
            }
        )
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: mock,
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot",
            arguments: [:],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "fullscreen_capture_failed")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC3: get_accessibility_tree 完整树

    // [P0] get_accessibility_tree returns AX tree with role/title/value/bounds/children
    func test_getAccessibilityTree_validWindowId_returnsAXTreeJson() async throws {
        let mockEngine = MockAccessibilityEngine(
            listWindowsHandler: { _ in [] },
            getWindowStateHandler: { _ in
                WindowState(
                    windowId: 100, pid: 1234, title: "Calculator",
                    bounds: WindowBounds(x: 0, y: 0, width: 300, height: 400),
                    isMinimized: false, isFocused: true,
                    axTree: AXElement(role: "AXWindow", title: "Calculator", value: nil,
                                     bounds: WindowBounds(x: 0, y: 0, width: 300, height: 400),
                                     children: [
                                        AXElement(role: "AXButton", title: "7", value: nil,
                                                  bounds: WindowBounds(x: 10, y: 50, width: 30, height: 30),
                                                  children: [])
                                     ])
                )
            },
            getAXTreeHandler: { windowId, maxNodes in
                AXElement(role: "AXWindow", title: "Calculator", value: nil,
                         bounds: WindowBounds(x: 0, y: 0, width: 300, height: 400),
                         children: [
                            AXElement(role: "AXButton", title: "7", value: nil,
                                     bounds: WindowBounds(x: 10, y: 50, width: 30, height: 30),
                                     children: [])
                         ])
            }
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: mockEngine,
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(100)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["role"] as? String, "AXWindow")
        XCTAssertEqual(json?["title"] as? String, "Calculator")
        XCTAssertNotNil(json?["bounds"], "AX tree should contain bounds")
        XCTAssertNotNil(json?["children"] as? [[String: Any]], "AX tree should contain children array")
    }

    // [P0] get_accessibility_tree passes window_id to service
    func test_getAccessibilityTree_passesCorrectWindowId() async throws {
        let box = Box<Int?>(value: nil)
        let mockEngine = MockAccessibilityEngine(
            listWindowsHandler: { _ in [] },
            getWindowStateHandler: { _ in
                WindowState(windowId: 1, pid: 1, title: nil,
                           bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
                           isMinimized: false, isFocused: false, axTree: nil)
            },
            getAXTreeHandler: { windowId, _ in
                box.value = windowId
                return AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
            }
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: mockEngine,
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(77)],
            context: makeTestContext()
        )

        XCTAssertEqual(box.value, 77, "Should pass window_id=77 to getAXTree")
    }

    // [P0] get_accessibility_tree for invalid window returns window_not_found error
    func test_getAccessibilityTree_windowNotFound_returnsErrorJson() async throws {
        let mockEngine = MockAccessibilityEngine(
            listWindowsHandler: { _ in [] },
            getWindowStateHandler: { _ in
                WindowState(windowId: 1, pid: 1, title: nil,
                           bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
                           isMinimized: false, isFocused: false, axTree: nil)
            },
            getAXTreeHandler: { windowId, _ in
                throw AccessibilityEngineError.windowNotFound(windowId: windowId)
            }
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: mockEngine,
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(99999)],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "window_not_found")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - AC4: get_accessibility_tree 截断

    // [P0] get_accessibility_tree passes max_nodes parameter to service
    func test_getAccessibilityTree_withMaxNodes_passesMaxNodesToService() async throws {
        let box = Box<Int?>(value: nil)
        let mockEngine = MockAccessibilityEngine(
            listWindowsHandler: { _ in [] },
            getWindowStateHandler: { _ in
                WindowState(windowId: 1, pid: 1, title: nil,
                           bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
                           isMinimized: false, isFocused: false, axTree: nil)
            },
            getAXTreeHandler: { _, maxNodes in
                box.value = maxNodes
                return AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
            }
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: mockEngine,
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(100), "max_nodes": .int(50)],
            context: makeTestContext()
        )

        XCTAssertEqual(box.value, 50, "Should pass max_nodes=50 to getAXTree")
    }

    // [P0] get_accessibility_tree defaults max_nodes to 500 when not specified
    func test_getAccessibilityTree_defaultMaxNodes_is500() async throws {
        let box = Box<Int?>(value: nil)
        let mockEngine = MockAccessibilityEngine(
            listWindowsHandler: { _ in [] },
            getWindowStateHandler: { _ in
                WindowState(windowId: 1, pid: 1, title: nil,
                           bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
                           isMinimized: false, isFocused: false, axTree: nil)
            },
            getAXTreeHandler: { _, maxNodes in
                box.value = maxNodes
                return AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
            }
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: mockEngine,
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(100)],
            context: makeTestContext()
        )

        XCTAssertEqual(box.value, 500, "Default max_nodes should be 500")
    }

    // MARK: - AC5: open_url URL 打开

    // [P0] open_url with valid https URL returns success
    func test_openUrl_validHttpsUrl_returnsSuccessJson() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url",
            arguments: ["url": .string("https://example.com")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["action"] as? String, "open_url")
        XCTAssertEqual(json?["url"] as? String, "https://example.com")
    }

    // [P0] open_url passes correct URL string to service
    func test_openUrl_passesCorrectUrl() async throws {
        let box = Box<String?>(value: nil)
        let mock = MockURLOpener(openURLHandler: { url in
            box.value = url
        })
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: mock
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "open_url",
            arguments: ["url": .string("https://example.com")],
            context: makeTestContext()
        )

        XCTAssertEqual(box.value, "https://example.com", "Should pass URL to openURL")
    }

    // [P0] open_url with invalid URL returns invalid_url error
    func test_openUrl_invalidUrl_returnsErrorJson() async throws {
        let mock = MockURLOpener(openURLHandler: { url in
            throw URLOpenerError.invalidURL(url)
        })
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: mock
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url",
            arguments: ["url": .string("not-a-url")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "invalid_url")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // [P0] open_url with unsupported scheme returns unsupported_scheme error
    func test_openUrl_unsupportedScheme_returnsErrorJson() async throws {
        let mock = MockURLOpener(openURLHandler: { url in
            throw URLOpenerError.unsupportedScheme(url)
        })
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: mock
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url",
            arguments: ["url": .string("ftp://example.com")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "unsupported_scheme")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // [P0] open_url failure to open returns failed_to_open error
    func test_openUrl_failedToOpen_returnsErrorJson() async throws {
        let mock = MockURLOpener(openURLHandler: { url in
            throw URLOpenerError.failedToOpen(url)
        })
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: mock
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url",
            arguments: ["url": .string("https://example.com")],
            context: makeTestContext()
        )

        let text = textContent(result)
        let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]

        XCTAssertEqual(json?["error"] as? String, "failed_to_open")
        XCTAssertNotNil(json?["message"])
        XCTAssertNotNil(json?["suggestion"])
    }

    // MARK: - No stub responses (Story 1.5 tools)

    // [P0] screenshot tool does not return "Not yet implemented" stub text
    func test_screenshot_doesNotReturnStubText() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot",
            arguments: ["window_id": .int(1)],
            context: makeTestContext()
        )

        let text = textContent(result)
        XCTAssertFalse(text.hasPrefix("Not yet implemented"), "Tool should not return stub text")
    }

    // [P0] get_accessibility_tree tool does not return "Not yet implemented" stub text
    func test_getAccessibilityTree_doesNotReturnStubText() async throws {
        let mockEngine = MockAccessibilityEngine(
            listWindowsHandler: { _ in [] },
            getWindowStateHandler: { _ in
                WindowState(windowId: 1, pid: 1, title: nil,
                           bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0),
                           isMinimized: false, isFocused: false, axTree: nil)
            },
            getAXTreeHandler: { _, _ in
                AXElement(role: "AXWindow", title: nil, value: nil, bounds: nil, children: [])
            }
        )
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: mockEngine,
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(1)],
            context: makeTestContext()
        )

        let text = textContent(result)
        XCTAssertFalse(text.hasPrefix("Not yet implemented"), "Tool should not return stub text")
    }

    // [P0] open_url tool does not return "Not yet implemented" stub text
    func test_openUrl_doesNotReturnStubText() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: makeSuccessScreenshotMock(),
            urlOpener: makeSuccessURLOpenerMock()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url",
            arguments: ["url": .string("https://example.com")],
            context: makeTestContext()
        )

        let text = textContent(result)
        XCTAssertFalse(text.hasPrefix("Not yet implemented"), "Tool should not return stub text")
    }
}

// MARK: - Sendable Box for capturing values in @Sendable closures

/// A thread-safe box for capturing values from @Sendable closures.
/// Used to work around Swift 6 strict concurrency checking in tests.
final class Box<T>: @unchecked Sendable {
    var value: T
    init(value: T) { self.value = value }
}
