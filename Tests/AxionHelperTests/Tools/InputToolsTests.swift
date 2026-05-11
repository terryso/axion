import Foundation
import MCP
import MCPTool
import XCTest
@testable import AxionHelper

// Unit tests for mouse/keyboard/drag/scroll MCP tools via mock services.
// All tools are tested through ToolRegistrar → MCPServer → execute pattern.

@MainActor
final class InputToolsTests: XCTestCase {

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

    private func mockInput(closure: @escaping @Sendable () throws -> Void = {}) -> MockInputSimulation {
        MockInputSimulation(
            clickHandler: { _, _ in try closure() },
            doubleClickHandler: { _, _ in try closure() },
            rightClickHandler: { _, _ in try closure() },
            scrollHandler: { _, _ in try closure() },
            dragHandler: { _, _, _, _ in try closure() },
            typeTextHandler: { _ in try closure() },
            pressKeyHandler: { _ in try closure() },
            hotkeyHandler: { _ in try closure() }
        )
    }

    // MARK: - click

    func test_click_success_returnsCoordinateResult() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: mockInput()
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "click", arguments: ["x": .int(100), "y": .int(200)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["success"] as? Bool, true)
        XCTAssertEqual(json["action"] as? String, "click")
        XCTAssertEqual(json["x"] as? Int, 100)
        XCTAssertEqual(json["y"] as? Int, 200)
    }

    func test_click_error_returnsErrorPayload() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: MockInputSimulation(
                clickHandler: { _, _ in throw InputSimulationError.coordinatesOutOfBounds(x: 9999, y: 9999) },
                doubleClickHandler: { _, _ in },
                rightClickHandler: { _, _ in },
                scrollHandler: { _, _ in },
                dragHandler: { _, _, _, _ in },
                typeTextHandler: { _ in },
                pressKeyHandler: { _ in },
                hotkeyHandler: { _ in }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "click", arguments: ["x": .int(9999), "y": .int(9999)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["error"] as? String, "coordinates_out_of_bounds")
        XCTAssertNotNil(json["message"])
        XCTAssertNotNil(json["suggestion"])
    }

    // MARK: - double_click

    func test_doubleClick_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "double_click", arguments: ["x": .int(50), "y": .int(60)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "double_click")
        XCTAssertEqual(json["success"] as? Bool, true)
    }

    // MARK: - right_click

    func test_rightClick_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "right_click", arguments: ["x": .int(10), "y": .int(20)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "right_click")
        XCTAssertEqual(json["success"] as? Bool, true)
    }

    // MARK: - type_text

    func test_typeText_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "type_text", arguments: ["text": .string("hello")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "type_text")
        XCTAssertEqual(json["text"] as? String, "hello")
    }

    func test_typeText_error_returnsErrorPayload() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: MockInputSimulation(
                clickHandler: { _, _ in },
                doubleClickHandler: { _, _ in },
                rightClickHandler: { _, _ in },
                scrollHandler: { _, _ in },
                dragHandler: { _, _, _, _ in },
                typeTextHandler: { _ in throw InputSimulationError.invalidKeyName("bad") },
                pressKeyHandler: { _ in },
                hotkeyHandler: { _ in }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "type_text", arguments: ["text": .string("x")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["error"] as? String, "invalid_key_name")
    }

    // MARK: - press_key

    func test_pressKey_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "press_key", arguments: ["key": .string("return")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "press_key")
        XCTAssertEqual(json["key"] as? String, "return")
    }

    // MARK: - hotkey

    func test_hotkey_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "hotkey", arguments: ["keys": .string("command+c")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "hotkey")
        XCTAssertEqual(json["keys"] as? String, "command+c")
    }

    func test_hotkey_invalidFormat_returnsError() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: MockInputSimulation(
                clickHandler: { _, _ in },
                doubleClickHandler: { _, _ in },
                rightClickHandler: { _, _ in },
                scrollHandler: { _, _ in },
                dragHandler: { _, _, _, _ in },
                typeTextHandler: { _ in },
                pressKeyHandler: { _ in },
                hotkeyHandler: { _ in throw InputSimulationError.invalidHotkeyFormat("xyz") }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "hotkey", arguments: ["keys": .string("xyz")], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["error"] as? String, "invalid_hotkey_format")
    }

    // MARK: - scroll

    func test_scroll_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "scroll", arguments: ["direction": .string("down"), "amount": .int(3)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "scroll")
        XCTAssertEqual(json["direction"] as? String, "down")
        XCTAssertEqual(json["amount"] as? Int, 3)
    }

    func test_scroll_invalidDirection_returnsError() async throws {
        let restore = ServiceContainerFixture.apply(
            inputSimulation: MockInputSimulation(
                clickHandler: { _, _ in },
                doubleClickHandler: { _, _ in },
                rightClickHandler: { _, _ in },
                scrollHandler: { _, _ in throw InputSimulationError.invalidDirection("sideways") },
                dragHandler: { _, _, _, _ in },
                typeTextHandler: { _ in },
                pressKeyHandler: { _ in },
                hotkeyHandler: { _ in }
            )
        )
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "scroll", arguments: ["direction": .string("sideways"), "amount": .int(1)], context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["error"] as? String, "invalid_direction")
    }

    // MARK: - drag

    func test_drag_success() async throws {
        let restore = ServiceContainerFixture.apply(inputSimulation: mockInput())
        defer { restore() }

        let server = try await makeRegisteredServer()
        let result = try await server.toolRegistry.execute(
            "drag",
            arguments: ["from_x": .int(0), "from_y": .int(0), "to_x": .int(100), "to_y": .int(100)],
            context: makeTestContext()
        )

        let json = try JSONSerialization.jsonObject(with: textContent(result).data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "drag")
        XCTAssertEqual(json["success"] as? Bool, true)
        XCTAssertEqual(json["from_x"] as? Int, 0)
        XCTAssertEqual(json["to_y"] as? Int, 100)
    }
}
