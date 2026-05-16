import Foundation
import MCP
import MCPTool
import Testing
@testable import AxionHelper
@testable import AxionCore

@MainActor
extension ToolsTests {
@Suite("ScreenshotUrlTool")
struct ScreenshotUrlToolTests {

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

    private let mockBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    private func makeSuccessScreenshotMock() -> MockScreenshotCapture {
        let base64 = mockBase64
        return MockScreenshotCapture(
            captureWindowHandler: { _ in base64 },
            captureFullScreenHandler: { base64 }
        )
    }

    private func makeSuccessURLOpenerMock() -> MockURLOpener {
        MockURLOpener(openURLHandler: { _ in })
    }

    @Test("screenshot with window id returns base64 JSON")
    func screenshotWithWindowIdReturnsBase64Json() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "screenshot")
        #expect((json?["image_data"] as? String) != nil)
    }

    @Test("screenshot with window id passes correct window id")
    func screenshotWithWindowIdPassesCorrectWindowId() async throws {
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

        #expect(box.value == 42)
    }

    @Test("screenshot invalid window id returns error JSON")
    func screenshotInvalidWindowIdReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "window_capture_failed")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("screenshot no window id returns full screen base64 JSON")
    func screenshotNoWindowIdReturnsFullScreenBase64Json() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "screenshot")
        #expect((json?["image_data"] as? String) != nil)
    }

    @Test("screenshot no window id calls capture full screen")
    func screenshotNoWindowIdCallsCaptureFullScreen() async throws {
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

        #expect(box.value == true)
    }

    @Test("screenshot full screen failure returns error JSON")
    func screenshotFullScreenFailureReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "fullscreen_capture_failed")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("get accessibility tree valid window id returns AX tree JSON")
    func getAccessibilityTreeValidWindowIdReturnsAXTreeJson() async throws {
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

        #expect(json?["role"] as? String == "AXWindow")
        #expect(json?["title"] as? String == "Calculator")
        #expect(json?["bounds"] != nil)
        #expect((json?["children"] as? [[String: Any]]) != nil)
    }

    @Test("get accessibility tree passes correct window id")
    func getAccessibilityTreePassesCorrectWindowId() async throws {
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

        #expect(box.value == 77)
    }

    @Test("get accessibility tree window not found returns error JSON")
    func getAccessibilityTreeWindowNotFoundReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "window_not_found")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("get accessibility tree with max nodes passes max nodes to service")
    func getAccessibilityTreeWithMaxNodesPassesMaxNodesToService() async throws {
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

        #expect(box.value == 50)
    }

    @Test("get accessibility tree default max nodes is 500")
    func getAccessibilityTreeDefaultMaxNodesIs500() async throws {
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

        #expect(box.value == 500)
    }

    @Test("open URL valid HTTPS returns success JSON")
    func openUrlValidHttpsReturnsSuccessJson() async throws {
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

        #expect(json?["success"] as? Bool == true)
        #expect(json?["action"] as? String == "open_url")
        #expect(json?["url"] as? String == "https://example.com")
    }

    @Test("open URL passes correct URL")
    func openUrlPassesCorrectUrl() async throws {
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

        #expect(box.value == "https://example.com")
    }

    @Test("open URL invalid URL returns error JSON")
    func openUrlInvalidUrlReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "invalid_url")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("open URL unsupported scheme returns error JSON")
    func openUrlUnsupportedSchemeReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "unsupported_scheme")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("open URL failed to open returns error JSON")
    func openUrlFailedToOpenReturnsErrorJson() async throws {
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

        #expect(json?["error"] as? String == "failed_to_open")
        #expect(json?["message"] != nil)
        #expect(json?["suggestion"] != nil)
    }

    @Test("screenshot does not return stub text")
    func screenshotDoesNotReturnStubText() async throws {
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
        #expect(!text.hasPrefix("Not yet implemented"))
    }

    @Test("get accessibility tree does not return stub text")
    func getAccessibilityTreeDoesNotReturnStubText() async throws {
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
        #expect(!text.hasPrefix("Not yet implemented"))
    }

    @Test("open URL does not return stub text")
    func openUrlDoesNotReturnStubText() async throws {
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
        #expect(!text.hasPrefix("Not yet implemented"))
    }
}
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(value: T) { self.value = value }
}
