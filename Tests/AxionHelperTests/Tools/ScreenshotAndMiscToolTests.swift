import Foundation
import MCP
import MCPTool
import Testing
@testable import AxionHelper
@testable import AxionCore

@MainActor
extension ToolsTests {
@Suite("ScreenshotAndMiscTool")
struct ScreenshotAndMiscToolTests {

    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

    private func makeTestContext() -> HandlerContext {
        let requestContext = RequestHandlerContext(
            sessionId: nil, requestId: .number(1), _meta: nil,
            taskId: nil, authInfo: nil, requestInfo: nil,
            closeResponseStream: nil, closeNotificationStream: nil,
            sendNotification: { _ in }, sendRequest: { _ in Data() }
        )
        return HandlerContext(handlerContext: requestContext, progressToken: nil)
    }

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { if case .text(let t, _, _) = $0 { return t }; return nil }.joined()
    }

    private let mockEngine = MockAccessibilityEngine(
        listWindowsHandler: { _ in [] },
        getWindowStateHandler: { _ in WindowState(
            windowId: 1, pid: 100, title: "T",
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false, isFocused: true, axTree: nil
        ) },
        getAXTreeHandler: { _, _ in AXElement(role: "AXWindow", title: "T", value: nil, bounds: nil, children: []) }
    )

    @Test("screenshot full screen returns base64")
    func screenshotFullScreenReturnsBase64() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: MockScreenshotCapture(
                captureWindowHandler: { _ in "window_b64" },
                captureFullScreenHandler: { "fullscreen_b64" }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot", arguments: nil, context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["action"] as? String == "screenshot")
        #expect(json["image_data"] as? String == "fullscreen_b64")
    }

    @Test("screenshot window returns base64")
    func screenshotWindowReturnsBase64() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: MockScreenshotCapture(
                captureWindowHandler: { _ in "window_b64" },
                captureFullScreenHandler: { "fullscreen_b64" }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot", arguments: ["window_id": .int(42)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["image_data"] as? String == "window_b64")
    }

    @Test("screenshot error returns error payload")
    func screenshotErrorReturnsErrorPayload() async throws {
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: MockScreenshotCapture(
                captureWindowHandler: { _ in throw ScreenshotError.windowCaptureFailed(windowId: 99) },
                captureFullScreenHandler: { throw ScreenshotError.fullScreenCaptureFailed }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "screenshot", arguments: ["window_id": .int(99)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["error"] as? String == "window_capture_failed")
    }

    @Test("get accessibility tree returns encoded tree")
    func getAccessibilityTreeReturnsEncodedTree() async throws {
        let tree = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError() },
                getAXTreeHandler: { _, _ in tree }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_accessibility_tree", arguments: ["window_id": .int(1)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["role"] as? String == "AXButton")
        #expect(json["title"] as? String == "OK")
    }

    @Test("get accessibility tree with max nodes")
    func getAccessibilityTreeWithMaxNodes() async throws {
        let tree = AXElement(role: "AXWindow", title: "W", value: nil, bounds: nil, children: [])
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError() },
                getAXTreeHandler: { wid, maxNodes in
                    #expect(maxNodes == 200)
                    return tree
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "get_accessibility_tree",
            arguments: ["window_id": .int(1), "max_nodes": .int(200)],
            context: makeTestContext()
        )
    }

    @Test("get accessibility tree default max nodes")
    func getAccessibilityTreeDefaultMaxNodes() async throws {
        let tree = AXElement(role: "AXWindow", title: "W", value: nil, bounds: nil, children: [])
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError() },
                getAXTreeHandler: { _, maxNodes in
                    #expect(maxNodes == 500)
                    return tree
                }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        _ = try await server.toolRegistry.execute(
            "get_accessibility_tree", arguments: ["window_id": .int(1)], context: makeTestContext()
        )
    }

    @Test("get accessibility tree error returns error payload")
    func getAccessibilityTreeErrorReturnsErrorPayload() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError() },
                getAXTreeHandler: { _, _ in throw AccessibilityEngineError.windowNotFound(windowId: 99) }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "get_accessibility_tree", arguments: ["window_id": .int(99)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["error"] as? String == "window_not_found")
    }

    @Test("open URL success")
    func openUrlSuccess() async throws {
        let restore = ServiceContainerFixture.apply(
            urlOpener: MockURLOpener(openURLHandler: { _ in })
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url", arguments: ["url": .string("https://example.com")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["url"] as? String == "https://example.com")
    }

    @Test("open URL error returns error payload")
    func openUrlErrorReturnsErrorPayload() async throws {
        let restore = ServiceContainerFixture.apply(
            urlOpener: MockURLOpener(openURLHandler: { _ in throw URLOpenerError.invalidURL("not-a-url") })
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "open_url", arguments: ["url": .string("not-a-url")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["error"] as? String == "invalid_url")
    }

    @Test("activate window success with window id")
    func activateWindowSuccessWithWindowId() async throws {
        let restore = ServiceContainerFixture.apply(accessibilityEngine: mockEngine)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "activate_window", arguments: ["pid": .int(123), "window_id": .int(45)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["pid"] as? Int == 123)
        #expect(json["window_id"] as? Int == 45)
    }

    @Test("activate window success without window id")
    func activateWindowSuccessWithoutWindowId() async throws {
        let restore = ServiceContainerFixture.apply(accessibilityEngine: mockEngine)
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "activate_window", arguments: ["pid": .int(123)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["success"] as? Bool == true)
        #expect(json["window_id"] == nil)
    }

    @Test("activate window error returns error payload")
    func activateWindowErrorReturnsErrorPayload() async throws {
        let restore = ServiceContainerFixture.apply(
            accessibilityEngine: MockAccessibilityEngine(
                listWindowsHandler: { _ in [] },
                getWindowStateHandler: { _ in fatalError() },
                getAXTreeHandler: { _, _ in fatalError() },
                activateWindowHandler: { _, _ in throw AccessibilityEngineError.appNotFound(pid: 999) }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "activate_window", arguments: ["pid": .int(999)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        #expect(json["error"] as? String == "app_not_found")
    }
}
}
